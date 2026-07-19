# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 7

Task: 7. Event-triggered publish + person grouping (Verification: full, rung 3)
Builder: plan-phase-builder (Fable), commit d4d97b9 (build/roadmap-t7) → master 133b8f4
(cherry-pick; union-resolved additive conflicts in config/.gitignore + cockpit.selftest.js,
node --check + composed suites green post-union: cockpit 139/0, server 165/0, peer-view ok).
Gates: pending (task-verifier + comprehension-reviewer).

## Builder-reported evidence (gates re-derive)

- Suites (all 0 failed): progress-log-lib 41 · progress-log CLI 6 · ask-registry 26 ·
  coord-sync 21 · peer-view 38 · export-state 11 (regression, unchanged) · cockpit 99
  (pre-union; 139 composed on master) · server 165.
- Red-green per cluster; mutation kills: debounce-removed mutant → 4 FAILs; naive
  "if clean: exit 0" floor mutant → floor scenarios FAIL.
- Flagless real-shape: coord-sync S1+S5 run the real exporter/push/pull against a fixture
  origin; S5b = event→publish E2E no stubs.
- Livesmoke: real server.js on test port → GET /api/asks returned
  persons=[{Misha:[desktop,laptop]},{unassigned:[mystery-box]}] through payload-schema
  validation; install-coord-sync-task.ps1 -WhatIf dry-run verified.
- export-state.js deliberately unchanged: existing hash-gate + 60min keepalive already
  satisfy peer-view's 80min window (PROVEN vs runExport + peer-view thresholds).

## Rung-3 articulation (builder-authored, verbatim-condensed)

**Spec meaning:** event path for status-changing writes at the ONE seam all writers share
(_ar_append_record / progress-log-lib); floor = FULL exporter cycle regardless of marker
(keepalive stamp only written when exporter runs; git-blind ops are markerless); clear
marker BEFORE export (lost-update); skips logged distinctly; 900s lock verified (> 5min
ExecutionTimeLimit, pinned S9); person grouping with named unassigned/map-error states.

**Edge cases covered:** dedup no-op doesn't mark; mid-export re-dirty; un-creatable marker
path (never-block); missing/garbled floor stamp = floor-due; unconfigured coord repo stays
at floor cadence; malformed/absent people map; case-insensitive hostnames; persons-absent
older payload; localStorage unavailable; burst coalescing; debounce-log rotation.

**Edge cases NOT covered:** backwards clock jump delays the floor by the jump size
(unbounded-clock case unguarded); one redundant republish when the triggering event
re-marks mid-cycle (harmless, hash-gated); Jaime-account access documented, not exercised.

**Assumptions:** until scheduled-task re-registration is applied, the floor governs but
quantizes to the OLD fire slots — idle full-cycle cadence degrades to ~600-1200s (worst
~20min export age, inside the 80min peer-unreachable honesty window); event latency
unchanged (next 600s fire); debounce.log starts appearing (comprehension gap-1 reword:
behavioral-identity claims only when the state machine is actually identical); env
tunables (COORD_SYNC_FLOOR_SECONDS, COORD_SYNC_DEBOUNCE_LOG_MAX_LINES) are trusted
numeric per house convention — a garbled FLOOR value would silence the floor (fails
toward silence, against the header law) — unguarded, operator-error class, numeric-guard
queued via nl-issue (gap-2 surface); t2's title verbs route through _ar_append_record and
inherit the marker; peer-view 80min window stays valid at any floor ≤ 60min keepalive.

## Orchestrator TODO (from builder, pending)

1. Per machine post-deploy: powershell -File adapters\claude-code\scripts\install-coord-sync-task.ps1
   -RepoPath "C:\Users\misha\dev\Pocket Technician\neural-lace" (operator-supervised class).
2. Verify Last Result 0 + coord-sync.sh --force → trigger=forced in cycles.log.
3. Populate workstreams-ui/config/people.json per machine.
4. Second-account access per docs/runbooks/coord-sync.md §Second-account.
5. Backlog row (builder barred): cockpit.selftest.js stripJsComments treats unclosed /*
   inside a // comment as block opener — class fix pending; instance defused asks.js:585.

## Gate results

### task-verifier: pending
### comprehension-reviewer: pending
