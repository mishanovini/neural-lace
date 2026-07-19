# Runbook: coord-sync — event-triggered cross-machine publish (+ periodic floor)

Owner: cockpit-roadmap-redesign Task 7 (round 5 operator intent, mechanics bound per
architecture-review amendment A5 —
`docs/reviews/2026-07-18-cockpit-roadmap-redesign-architecture-review.md` F5).

## How it works (the hybrid)

Three cooperating pieces:

1. **Dirty marker at the writer-lib seam** (`~/.claude/state/coord-sync/dirty`).
   Touched by `adapters/claude-code/hooks/lib/progress-log-lib.sh` (`pl_emit`, fresh
   appends only — dedup no-ops never mark) and `adapters/claude-code/scripts/
   ask-registry.sh` (`_ar_append_record`, every verb). NOT a hook splice — the
   writer-lib seam also covers the GUI's delegated CLI writes and every future
   writer (A5 iii). The touch is never-blocking: pure local fs, no git/network,
   all failures swallowed. Override for tests/both ends at once:
   `COORD_DIRTY_MARKER_FILE`.
2. **Debounced publisher** — the `NL-CoordSync` scheduled task fires
   `adapters/claude-code/scripts/coord-sync.sh` every ~60s. Each fire is a cheap
   marker check:
   - marker present → FULL cycle (exporter → coord-push → coord-pull), marker
     removed **BEFORE** the exporter reads state (A5 ii — a mid-export event
     re-dirties and the next fire republishes; clear-after loses updates).
     Publish latency after a real status change: ~1 min. Bursts coalesce (N
     events → one marker → one cycle); the exporter's content-hash gate is
     unchanged.
   - clean, floor not due → marker-check-only no-op, logged to
     `STATE_DIR/debounce.log` (own rotation) — **never** `cycles.log`, which
     stays one-line-per-full-cycle (its `trigger=` field says event/floor/forced).
3. **Periodic floor** — a FULL cycle runs at least every
   `COORD_SYNC_FLOOR_SECONDS` (default 600) **regardless of the marker** (A5 i).
   Two proven reasons: the A3ii keepalive stamp is only written when the exporter
   runs (`neural-lace/workstreams-ui/server/export-state.js` `runExport`,
   KEEPALIVE_MS=60min) — a naive "if clean: exit 0" freezes `exported_at` and a
   healthy idle machine renders **peer-unreachable** within ~80min
   (`server/peer-view.js` classifyPeerState); and git-blind mutations
   (cherry-pick/pull/reset) fire no event — the floor is their only coverage.
   A missing/garbled floor stamp counts as floor-due (fails toward publishing).

Heartbeat-only changes (session liveness) deliberately ride the floor, not the
event path — only status-changing writes touch the marker.

Lock: the mkdir lock + `-MultipleInstances IgnoreNew` bound overlap; the 900s
stale-lock reclaim stays valid at the 60s cadence because the task's
ExecutionTimeLimit (5 min) hard-bounds any live cycle (self-test Scenario 9 pins
900s > that limit mechanically).

## Registration (per machine — OPERATOR/orchestrator-applied)

Agent sessions must NOT run this (scheduled-task mutation = persistence); they
verify with `-WhatIf` only.

```powershell
powershell -File adapters\claude-code\scripts\install-coord-sync-task.ps1 `
  -RepoPath "<absolute path to the MAIN neural-lace checkout>"
```

This follows the wrapper pattern from `docs/runbooks/session-resumer.md`
§Registration (hidden-window vbs + space-free `.cmd` under
`%USERPROFILE%\.claude\state\task-wrappers\`) and registers/updates
`NL-CoordSync` at a 60s repetition. Re-running is idempotent; machines still on
the old 600s registration keep working (the script itself floors at 600s) but
lose the ~1min event path until re-registered.

Verify after applying:

```powershell
Get-ScheduledTask -TaskName 'NL-CoordSync'
schtasks /Query /TN NL-CoordSync /V | findstr "Last Result"   # 0 = healthy
```

```bash
bash adapters/claude-code/scripts/coord-sync.sh --force   # one guaranteed full cycle
tail -n 3 ~/.claude/state/coord-sync/cycles.log            # trigger=forced line
tail -n 3 ~/.claude/state/coord-sync/debounce.log          # marker-check-only fires
```

## Person grouping (round 5: "Misha: desktop + laptop")

Peers group by PERSON in the cockpit's Peers pane. Map lives in
`neural-lace/workstreams-ui/config/people.json` (per-machine, gitignored; copy
`people.example.json`), keys = hostnames (case-insensitive), values = display
names. Unmapped hostnames render under the named `unassigned` group; a
malformed map file renders a labeled error naming the file, machines degrade to
`unassigned` (never a guessed person). Env override: `COCKPIT_PEOPLE_FILE`.

## Second-account (second person's) coord-repo access

The coordination transport is the private `workstreams-coordination` git repo
(URL per machine in `~/.claude/local/coord-repo-url.txt`, or `COORD_REPO_URL`).
To bring a second person's machines into the peer view:

1. On the repo host (the private repo's owning account), grant the second
   person's account **write** access (collaborator or team grant) — coord-push
   needs push, coord-pull needs fetch.
2. On each of their machines: authenticate that account for git
   (`gh auth login` or SSH key), then write the clone URL to
   `~/.claude/local/coord-repo-url.txt` (first line, no quotes).
3. Register `NL-CoordSync` there (section above). Their exports appear as
   `plan-export/<their-hostname>.json`; add their hostnames to each machine's
   `config/people.json` to group them under their name.

No server-side changes are needed — N-machine is the shipped architecture
(per-hostname export files; every non-self file renders as a peer).

## Tunables

| Env | Default | Meaning |
| --- | --- | --- |
| `COORD_SYNC_FLOOR_SECONDS` | 600 | max seconds between FULL cycles (the A5 floor) |
| `COORD_DIRTY_MARKER_FILE` | `~/.claude/state/coord-sync/dirty` | marker path (writers + publisher share it) |
| `COORD_SYNC_DEBOUNCE_LOG_MAX_LINES` | 300 | debounce.log rotation cap |
| `COORD_SYNC_LOCK_STALE_SECONDS` | 900 | stale-lock reclaim (must exceed the task's ExecutionTimeLimit) |
| `-IntervalSeconds` (installer) | 60 | scheduled-task fire interval (the debounce quantum) |

Self-tests: `bash adapters/claude-code/scripts/coord-sync.sh --self-test` (floor,
clear-before-export, coalescing, lock invariant — Scenarios 5-9),
`bash adapters/claude-code/hooks/lib/progress-log-lib.sh --self-test` (marker
seam — Scenario 17), `bash adapters/claude-code/scripts/ask-registry.sh
--self-test` (Scenario Q), `node server/peer-view.js --self-test` (person
grouping — Scenarios 16-18).
