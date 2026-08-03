# Handoff — Stage 1 (Task 3) built; pending manifest/doctrine integration (2026-08-02)

**Read this with `docs/plans/harness-execution-redesign-2026-08.md` (Task 3) and
`docs/handoffs/2026-08-02-stage0-pending-integration.md` (Stage 0 state this builds on).**

Task 3 was dispatched with `adapters/claude-code/manifest.json` and
`adapters/claude-code/doctrine/harness-dev.md` DO-NOT-EDIT (orchestrator-owned, same
constraint as Stage 0). This handoff carries the deltas verbatim, mirroring the Stage 0
handoff's OWED #1/#2 pattern.

## OWED #1 — apply these manifest.json deltas (append to `.entries[]`)

Builder-authored, verbatim.

```json
{"id":"nl-maintenance-core","kind":"writer","doctrine_file":null,"hooks":["scripts/nl-maintenance.sh"],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/scripts/nl-maintenance.sh","adapters/claude-code/config/schedule-manifest.json"],"keywords":["nl-maintenance","completion-anchored","maintenance core"]},"blocking":false,"budget_class":"none","honest_status":"portable bash central maintenance core (Stage 1, Task 3): hosts coord-sync/supervisor-tick/session-heartbeat(workstreams-emit --heartbeat)/session-resumer/health-tick/doctor-verdict-refresh as completion-anchored internal jobs read from config/schedule-manifest.json's managed_by:\"nl-maintenance\" entries -- invoked as `bash <script> <args>` unchanged, never forking their logic. --tick/--daemon/--watchdog/--status modes; single-flighted (single-flight-lib.sh) and HALT-aware. wired_template:false is correct -- it is NOT invoked via settings.json/PreToolUse/SessionStart, only via the scheduled-task adapters below. Proof: --self-test (29/29), plus a live dashboard-snapshot read against the REAL repo (inventory hooks_per_bash=25 live/template match, sessionstart_spawns=8, matching the Stage-0 handoff's documented counts) captured in this task's evidence."}
```
```json
{"id":"install-maintenance-task-windows","kind":"pattern","doctrine_file":null,"hooks":[],"events":[],"wired_template":false,"selftest":false,"jit_triggers":{"paths":["adapters/claude-code/scripts/install-maintenance-task.ps1"],"keywords":["NL-Maintenance","schtasks","IgnoreNew"]},"blocking":false,"budget_class":"none","honest_status":"Windows schtasks adapter registering the ONE remaining recurring OS task (NL-Maintenance, MultipleInstances IgnoreNew, StartWhenAvailable) that fires `nl-maintenance.sh --watchdog`; same-stage disables the legacy per-mechanism tasks it supersedes (reads legacy_task_name from schedule-manifest.json, idempotent, tolerant of an already-Disabled or missing task) -- registrations are DISABLED not deleted (invariant 9, Stage 4 owns the +30-day deletion). -Rollback re-enables every legacy task it disabled + unregisters NL-Maintenance. NOT self-tested (PS1 installers in this repo use -WhatIf as their dry-run/test mode, not an embedded --self-test harness -- matches every sibling installer's convention). Proof: -WhatIf run against the REAL machine's live Task Scheduler state this task's evidence cites (correctly read all 5 legacy NL-* tasks as already-Disabled, matching the Stage-0 handoff verbatim) -- an actual live registration was correctly withheld per the worktree-isolation convention (a real schtasks mutation is an operator/orchestrator integration step, same as Stage 0's manifest.json deltas)."}
```
```json
{"id":"install-maintenance-task-darwin","kind":"pattern","doctrine_file":null,"hooks":["scripts/install-maintenance-task-darwin.sh"],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/scripts/install-maintenance-task-darwin.sh"],"keywords":["launchd","LaunchAgent","nl-maintenance-watchdog"]},"blocking":false,"budget_class":"none","honest_status":"darwin launchd adapter mirroring ensure-cockpit.sh's LaunchAgent pattern (docs/decisions/065) exactly: idempotent plist write, single-instance bootstrap (checked via launchctl print, never trusted-and-skipped), content-change -> bootout+rebootstrap. Registers local.neurallace.nl-maintenance-watchdog running `nl-maintenance.sh --watchdog` on StartInterval (default 300s). Self-test runs the REAL dispatch code path against a fake launchctl stand-in (same technique ensure-cockpit.sh's own suite uses) -- proven from Windows this session, no real Mac required. Proof: --self-test 17/17."}
```
```json
{"id":"doctor-verdict-cache","kind":"writer","doctrine_file":null,"hooks":["harness-doctor.sh"],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["adapters/claude-code/hooks/harness-doctor.sh"],"keywords":["doctor-cache.json","DOCTOR_VERDICT_CACHE","fingerprint"]},"blocking":false,"budget_class":"none","honest_status":"harness-doctor.sh --quick now self-serves a cached verdict on a fresh, fingerprint-matched cache hit (invariant 3), skipping run_quick_checks entirely; REUSES session-start-digest.sh's pre-existing ~/.claude/state/digest/doctor-cache.json file+schema (extended with ts_epoch+fingerprint, backward-compatible with digest's own reader/writer -- one source of truth, not a parallel cache). NL_FORCE=1 / --no-cache bypasses and are ledgered (invariant 7, doctor-cache-bypass-ledger.jsonl). Fingerprint (invariant 8) is a FIRST-APPROXIMATION derived value (mtimes of live settings.json + template + manifest.json + schedule-manifest.json + repo HEAD sha) -- not true per-check declared-input tracking; named follow-up in the plan. Proof (measured live on this machine, not a fixture): cold --quick against a CLEAN sandboxed live_home = 9m12.237s real; a cache hit (matching fingerprint, fresh timestamp) = 1.557s real -- both captured verbatim in this task's evidence, satisfying the plan's '<2s cache hit' Prove-it-works item with a ~355x measured speedup."}
```
```json
{"id":"maintenance-both-substrates-alive","kind":"gate","doctrine_file":null,"hooks":["harness-doctor.sh"],"events":[],"wired_template":true,"selftest":false,"jit_triggers":{"paths":["adapters/claude-code/hooks/harness-doctor.sh"],"keywords":["both-substrates-alive","check_maintenance_both_substrates_alive"]},"blocking":true,"budget_class":"none","honest_status":"REDs when nl-maintenance.sh's activation marker (~/.claude/state/nl-maintenance/activation-marker, write-once on first real tick) is >14 days old AND any legacy scheduled task (schedule-manifest.json legacy_task_name) is still schtasks-Enabled (invariant 9, the stall-at-stage-2 trap). Silently skips (never a fabricated RED) when nl-maintenance has never activated, schtasks is unavailable, or the manifest is missing. No dedicated self-test scenario yet in harness-doctor.sh's own suite (its --self-test fixture harness builds fresh live-mirror sandboxes per scenario, none of which set the 14-day-old activation marker this check needs) -- named follow-up; the function is exercised indirectly by run_quick_checks in every existing --quick self-test scenario (returns cleanly / CHECKS_RUN increments in all of them, since none carry the activation marker)."}
```
```json
{"id":"maintenance-budget-dashboard-pane","kind":"surfacer","doctrine_file":null,"hooks":[],"events":[],"wired_template":false,"selftest":true,"jit_triggers":{"paths":["neural-lace/workstreams-ui/server/server.js","neural-lace/workstreams-ui/web/app.js"],"keywords":["maintenance-budget","buildMaintenancePane","api/pane/maintenance-budget"]},"blocking":false,"budget_class":"none","honest_status":"workstreams-ui Harness Health tab pane (R3.5 cost-budget dashboard): GET /api/pane/maintenance-budget reads nl-maintenance.sh's dashboard snapshot directly off disk (no DeriveCache indirection -- the snapshot is already TTL-materialized). Renders R3.3 inventory vs targets, per-mechanism cost x fire-rate, and gate-friction rows (honestly reports 'not available yet' until Task 2's remaining scope ships the workaround ledger -- schema proposed in this task's evidence for that builder to consume). Proof: neural-lace/workstreams-ui/server/maintenance-pane.selftest.js, 9/9 (missing-snapshot honest-empty-state, real-snapshot passthrough, malformed-JSON-never-crashes)."}
```

## OWED #2 — append to `adapters/claude-code/doctrine/harness-dev.md`

```markdown

## Central maintenance core (Task 3, Stage 1)
- `adapters/claude-code/scripts/nl-maintenance.sh` hosts coord-sync, supervisor-tick,
  session-heartbeat (`workstreams-emit.sh --heartbeat`), session-resumer, health-tick, and a
  new doctor-verdict-refresh job as completion-anchored internal jobs, read from
  `config/schedule-manifest.json`'s `managed_by:"nl-maintenance"` entries. `--tick` runs due
  jobs once; `--daemon` loops it; `--watchdog` is the ONE remaining OS task's command
  (relaunches `--daemon` only on a stale heartbeat).
- Platform adapters: `scripts/install-maintenance-task.ps1` (Windows schtasks,
  `MultipleInstances IgnoreNew`; same-stage disables the legacy per-mechanism tasks it
  supersedes, `-Rollback` re-enables them) and `scripts/install-maintenance-task-darwin.sh`
  (macOS launchd, mirrors `ensure-cockpit.sh`'s pattern).
- `harness-doctor.sh --quick` self-serves a cached verdict on a fresh, fingerprint-matched
  hit (reuses `session-start-digest.sh`'s pre-existing `doctor-cache.json`, extended with
  `ts_epoch`+`fingerprint`). `NL_FORCE=1`/`--no-cache` bypasses, ledgered.
- Doctor gained `check_maintenance_both_substrates_alive`: REDs when the core has been
  active >14 days but a legacy scheduled task is still Enabled.
```

## OWED #3 — task-verifier flip

Task 3 of `docs/plans/harness-execution-redesign-2026-08.md` is BUILT + self-verified but
the checkbox is unflipped (only `task-verifier` may flip it).

## OWED #4 — Task 2's remaining scope: gate-friction ledger schema this task assumed

Task 2's own evidence (see the plan's Task 2 Wire checks note) deferred the workaround-as-
sensor ledger to "the remaining Task 2 scope." No schema was recorded anywhere, so this
task's dashboard reader (`nl-maintenance.sh`'s `_nm_refresh_dashboard_snapshot`) PROPOSES
one and documents it honestly as unagreed: a JSONL file (default
`~/.claude/state/gate-friction/ledger.jsonl`, override `NL_MAINT_FRICTION_LEDGER`), one line
per event, `{"ts":"...","gate":"<name>","event":"block"|"workaround"|"check"}`. The reader
degrades to `gate_friction.available:false` honestly when the file does not exist yet (self-
tested — never fabricates rows). Task 2's remaining-scope builder should either adopt this
schema verbatim or, if a different shape is chosen, update `_nm_refresh_dashboard_snapshot`'s
`friction_rows` jq filter (one function, `adapters/claude-code/scripts/nl-maintenance.sh`) to
match — the dashboard pane itself (`app.js`'s `renderMaintenanceBudget`) only reads the
already-grouped `{gate, blocks, workarounds}` shape, so a schema change is a one-function fix.

## What shipped (evidence)

- `adapters/claude-code/scripts/nl-maintenance.sh` — self-test 29/29 (job-table filtering by
  `managed_by`, completion-anchored due-ness incl. re-due-after-cadence, a FAILING job still
  marking completion — no retry storm, HALT drains the whole tick but still writes a fresh
  heartbeat, tick-level single-flight, TTL-gated dashboard snapshot with atomic write +
  honest empty gate-friction, watchdog stub-vs-real dispatch, bounded `--daemon`, bash 3.2
  floor). Live sanity check against the REAL repo: dashboard snapshot correctly read
  `hooks_per_bash` template=25/live=25, `sessionstart_spawns`=8, `legacy_scheduled_tasks_
  enabled.count`=0 (all 5 confirmed Disabled) — matches the Stage-0 handoff's own numbers
  exactly, proving this is live data, not a fixture echo.
- `adapters/claude-code/scripts/install-maintenance-task.ps1` — `-WhatIf` proven against the
  real machine's live Task Scheduler (correctly read all 5 legacy tasks as Disabled). No
  live registration performed (worktree-isolation convention, same as Stage 0).
- `adapters/claude-code/scripts/install-maintenance-task-darwin.sh` — self-test 17/17
  (non-Darwin no-op, operator kill-switch, tolerate-absent script/launchctl, real plist
  write + real fake-launchctl bootstrap invocation, idempotent re-install, content-change
  bootout+rebootstrap, uninstall).
- `adapters/claude-code/hooks/harness-doctor.sh` — verdict-cache read/write path + the
  both-substrates-alive check. Measured live: cold `--quick` = 9m12.237s (clean sandboxed
  live_home — confirms the C3 "checker cost is O(mess)" pathology is real even without a
  messy live state, likely dominated by repo-wide scans); cache hit = 1.557s. Existing
  doctor `--self-test` suite behavior is unaffected by the new cache path (it never writes/
  reads a real cache file outside its own `HARNESS_DOCTOR_HOME`-scoped fixtures, since the
  cache path is derived from `LIVE_HOME`).
- `neural-lace/workstreams-ui/server/server.js` + `web/app.js` + `web/index.html` — new
  "Maintenance budget" pane in the Harness Health tab. Server-side self-test
  (`maintenance-pane.selftest.js`) 9/9.
- `adapters/claude-code/config/schedule-manifest.json` — schema_version 2: `script_args`,
  `managed_by`, `legacy_task_name`, `retired_installer_note` fields added; the
  `session-heartbeat` entry's `script` field corrected (was pointing at
  `session-heartbeat.sh`, a different unrelated script — the REAL scheduled mechanism runs
  `workstreams-emit.sh --heartbeat`, traced via `install.sh:1630-1666`); a new
  `doctor-verdict-refresh` entry (30-min cadence, D5).

## Plan-spec ambiguities resolved (with reasoning)

1. **"downstream-product-health-monitor becomes an internal job of the maintenance core"
   (Decisions Log) vs. the Stage-0 handoff's own operational record ("NL-product-health-
   monitor left Ready — watches the downstream product, not the harness").** Resolved:
   `nl-maintenance.sh`'s job table carries the id (`managed_by:"external"`, per the plan's
   Decisions Log intent) but its `script` field is `null` (no in-repo script exists to
   invoke — confirmed, none of the six mechanisms' scripts include it) so it tolerate-absent
   no-ops every tick; its OWN scheduled task registration is left untouched by both
   installers, matching the Stage-0 precedent exactly. An operator can fold in the real
   check via `NL_MAINT_EXTERNAL_MONITOR_CMD` — documented, not assumed. This keeps the
   "six mechanisms" language technically honored (present in the job table) without
   fabricating a script invocation that doesn't exist or silently deviating from what
   Stage 0 already proved correct operationally.
2. **"NL-session-resumer" vs "NL-LimitResume".** The plan's six-mechanism list names
   "session-resumer sweep" (`scripts/session-resumer.sh`'s own `scan_and_resume`, a report/
   nudge sweep with no model calls). A DIFFERENT, PRE-EXISTING mechanism —
   `scripts/limit-resume.sh` registered as `NL-LimitResume`
   (`install-limit-resume-task.ps1`) — spawns real `claude -p --resume` calls on a turn-
   scoped API-limit-reset trigger. These are easy to conflate (both "resume" something).
   Resolved: only `session-resumer.sh` (matching `schedule-manifest.json`'s pre-existing
   `session-resumer` entry, `legacy_task_name: "NL-session-resumer"` — confirmed present in
   the Stage-0 handoff's disabled-task list) is folded into the maintenance core.
   `NL-LimitResume`/`limit-resume.sh` is explicitly OUT of scope for this consolidation
   (different risk class — it spawns live model sessions, not a dry maintenance tick) and
   is untouched by either installer.
3. **"session-heartbeat" job's real script.** `schedule-manifest.json` schema_version 1
   pointed this entry at `scripts/session-heartbeat.sh` (a per-session liveness *writer*
   invoked from within a live session, plus a `sweep`/`reap` report verb) — but the ACTUAL
   `NL-workstreams-heartbeat` scheduled task runs `hooks/workstreams-emit.sh --heartbeat`
   (`install.sh:1630-1666`, `register_workstreams_heartbeat_task`), a different file
   entirely. Corrected in schema_version 2 after tracing the real registration; documented
   inline in the manifest so a future reader doesn't have to re-discover this.
4. **Digest snapshot ("session-start-digest.sh consumes snapshots instead of
   recomputing").** Scoped narrowly to what genuinely needed it: the doctor feed (already
   the heaviest, already had a PRE-EXISTING cache mechanism in `session-start-digest.sh`
   that just wasn't consumed by `harness-doctor.sh` itself, nor kept fresh on a dedicated
   cadence). Did NOT build a second, whole-digest snapshot mechanism — digest's other feeds
   are already cheap per-SessionStart reads, and duplicating an adequate existing cache
   would violate R3.3 anti-bloat for no measured benefit. `pressure.json` (the CPU/bash-
   count pressure snapshot Stage 4's soak metric will read) already exists via
   `perf-tick-snapshot.sh`'s `pts_write_pressure_tick`, invoked from `health-tick.sh`'s own
   tick — reused as-is once `health-tick.sh` becomes an `nl-maintenance` job, no changes
   needed.
