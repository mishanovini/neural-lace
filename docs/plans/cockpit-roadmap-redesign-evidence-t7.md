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

### task-verifier: pending (Fable, in flight). NOTE: harness-review F1 (coord-sync × coord-push throttle composition defeats A5 ~1-min publish + starves A2c alert streak; suites masked via THROTTLE=0) = defect in this task's goal — fix dispatched (sonnet build/harness-reform-f123: coord-push push --force in _run_cycle + throttle-ACTIVE scenarios + outcome word throttled). Checkbox HELD until F1 lands regardless of verifier verdict.
### comprehension-reviewer DELTA (Fable): PASS conf 8 — both prior gaps resolved, 6/6 citations grounded, flip authorized from comprehension side.

## F1-resolution — hold released (task-verifier re-verify, 2026-07-20)

The task-7 checkbox was HELD solely on harness-review F1 (the coord-sync × coord-push
throttle-composition defect above — A5 ~1-min publish swallowed by coord-push's own 600s
throttle; A2c local-commit streak starved by throttled-as-noop; both masked by the
self-tests' `COORD_PUSH_THROTTLE_SECONDS=0`). F1 is now FIXED and landed. The hold is
released with this record.

**Fix (merged to master):** `09f29b7` — `fix(coord-sync F1): event cycle pushes with --force`.
Live blobs on HEAD (fd9c3e5): coord-sync `5a9ba6b8be22d9ab4f17111d1ef7de56f272b018`,
coord-push `79245cdb892a6679cc3d4d3a2e578a9c999d3a00` — byte-identical to the review record's
covered_files. What it changes, mapped to the review's REQUIRED-FIX 1-4:
- REQUIRED-FIX 1: `_run_cycle` invokes `coord-push push --force` (coord-sync.sh:462) — the
  event/floor cycle bypasses coord-push's OWN throttle (coord-sync's debounce+floor is already
  the single per-machine rate limiter); every other coord-push WARN+exit-0 degradation path is
  untouched (a plain non-force `git push`, §9-safe — confirmed by the delta reviewer).
- REQUIRED-FIX 2: coord-push's throttle early-return now writes the DISTINCT outcome word
  `throttled` (coord-push.sh:296), not `noop` — "never even checked" is no longer bucketed with
  "checked, genuinely nothing to publish".
- REQUIRED-FIX 3b: coord-sync's `_track_local_commit_streak` treats `throttled` as NO-SIGNAL
  (coord-sync.sh:313 elif branch) — the streak (and any active-alert dedup) is preserved, never
  reset, so a dead remote's rapid retries still cross the A2c threshold.
- Suite un-masking: NEW self-test Scenarios S10 (coord-sync + coord-push) and S11 run with the
  throttle at its DEFAULT 600s (never overridden to 0) — the guard is genuinely ACTIVE.

**Review records (registered in docs/reviews/records/index.json):**
- Root-cause: `frc-20260720-01301d50` (fix-root-cause, PASS, PROVEN) — root cause pinned at
  coord-push.sh:71/283-291, coord-sync.sh:432, mask at coord-sync.sh:518/663/681.
- Delta review: `hcr-20260720-79170b4e` (harness-change-review, PASS) — "REQUIRED-FIX 1-4 are
  each implemented exactly as specced; the --force flag is confirmed to bypass only coord-push's
  throttle; nothing rode along." Both records cover the exact live blobs above.
- Review write-up: `docs/reviews/2026-07-20-f1-f3-rederived-harness-review.md`. FRC record commit
  `8b83e76`; delta-review record commit `fd9c3e5`.

**Suites re-run directly by the verifier (NOT trusting the recorded exit-0 — the originating
defect was literally "suites masked via THROTTLE=0", which is standing reason to distrust green
runs on this exact surface). Hooks neutralized for child git (`GIT_CONFIG` core.hooksPath="")
per NL-FINDING-029; otherwise fixture commits hang:**
- `bash adapters/claude-code/scripts/coord-push.sh --self-test` → **14 passed, 0 failed (exit 0)**,
  including the new S10 pair: "throttle early-return (fresh LAST_PUSH_FILE, DEFAULT 600s window)
  writes outcome=throttled, not noop" and "throttled push never attempted a git operation".
- `bash adapters/claude-code/scripts/coord-sync.sh --self-test` → **25 passed, 1 failed (exit 1)**.
  The two F1 scenarios are GREEN: S10 "event cycle <600s after a prior push STILL advances origin
  (payload B) — --force bypasses coord-push's callee throttle, guard ACTIVE (DEFAULT 600s, never
  overridden)" + "second cycle's status file records outcome=pushed"; S11 "throttled outcomes are
  no-signal: streak counts ONLY the 4 real local-commit cycles (2 throttled interruptions did not
  reset it)" + "dead-remote streak … still crosses threshold 3 → exactly ONE A2c alert fires".
  The single FAIL is Scenario 5a ("clean fire inside the floor window → marker-check-only no-op"),
  a PROVEN test-timing artifact of THIS environment, NOT a code defect and NOT F1: this run took
  ~52 minutes wall-clock (12:25:19 → 13:17:10) on a slow git-fixture host; 5a reuses Scenario 1's
  floor stamp with no `COORD_SYNC_FLOOR_SECONDS` override, so once the intervening slow scenarios
  (1's real full cycle + 3's 5+ consecutive cycles) push wall-clock past the 600s floor, the floor
  is genuinely DUE and a clean fire CORRECTLY runs a full cycle instead of a marker-check-only skip
  ("fail toward publishing"). The mechanism 5a tests is independently GREEN in the same run:
  Scenario 6 assertion 2 ("floor fresh + still clean → exporter NOT run again (debounce)") and
  Scenario 8 ("8 clean fires → zero extra cycles; debounce.log rotated"), both of which control
  their own fresh floor stamps. Filed via nl-issue (Scenario 5a timing fragility on slow hosts).

**Re-verify checklist from the prior held FAIL (canonical evidence, Task 7 block), all met:**
(a) `_run_cycle` push leg bypasses/overrides the throttle on event cycles → coord-sync.sh:462
`--force`, S10 green. (b) ≥1 coord-sync scenario runs with the throttle ACTIVE (no THROTTLE=0 mask)
asserting the event publish reaches origin within one fire → S10, guard active, payload B on origin.
(c) throttled outcome word no longer resets the A2c streak → S11 green. (d) re-run coord-sync +
coord-push suites → done (above); F1 touched no server file (09f29b7 = coord-sync.sh + coord-push.sh
+ runbook only), so the prior server 165/0 · peer-view 38/0 · cockpit-PV person-grouping results
STAND. (e) re-flip via a fresh evidence entry → canonical evidence Task 7 RE-VERIFY block +
this record, same commit as the checkbox flip.

**Verdict: PASS, confidence 9.** All prior verification axes STAND; the sole hold (F1) is resolved,
landed, record-covered, and independently re-exercised green with the throttle guard ACTIVE.
