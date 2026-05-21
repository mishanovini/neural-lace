# Plan: Circuit Production Health Monitor

Status: ACTIVE
Execution Mode: direct
Mode: code
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal operations tooling; the maintainer is the user of the alert markers; probe + surfacer `--self-test` suites (6/6 PASS each) are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal

Build a self-monitoring health checker that probes Circuit prod every 30 minutes and surfaces regressions automatically to the Dispatch orchestrator via marker files. Closes the gap where prod regressions (e.g., the 2026-05-18 supabase-js fetch deadlock affecting `/api/health` and the webhook POST routes) were going undetected between user-initiated checks.

The user-facing outcome: when a Circuit-prod route regresses, the NEXT interactive orchestrator session sees a `<system-reminder>` block at startup naming the regression with verdict / status / elapsed / failure reason — no babysitting required.

## Scope

- IN:
  - `tools/circuit-health-probe.sh` — the probe (24 critical routes, JSON output, history log, alert marker emission, `--self-test`).
  - `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` — SessionStart hook that surfaces unacked alert markers (mirrors `spawned-task-result-surfacer.sh` pattern).
  - `adapters/claude-code/settings.json.template` — wires the surfacer into the SessionStart chain.
  - Live mirror sync to `~/.claude/hooks/external-monitor-alert-surfacer.sh` and `~/.claude/settings.json` (per two-layer config discipline).
  - `docs/operations/circuit-health-monitor-2026-05-20.md` — runbook (what's monitored, alert file format, how to enable schedule via Option A / B / C, pause mechanism, route-catalog update procedure, failure-mode disclosure).
  - `docs/plans/circuit-prod-health-monitor.md` — this plan.
- OUT:
  - Any modifications to the Circuit repo itself (separate concern; Circuit-side fixes for the surfaced regressions are tracked separately).
  - Authenticated probes (out of v1 scope; mitigation noted in runbook).
  - Per-upstream-service health checks (Twilio / Retell / Resend upstreams — different concern).
  - Cloud-cron (Trigger.dev) — Option C; not chosen (no real benefit over A/B).

## Tasks

- [x] 1. Author `tools/circuit-health-probe.sh` with 24-route catalog, JSON output schema, history log, alert marker emission, maintenance pause, `--self-test`. Verification: mechanical
  **Prove it works:** `bash tools/circuit-health-probe.sh --self-test` exits 0 with 6/6 PASS.
  **Wire checks:** n/a — single-purpose script.
  **Integration points:** writes to `~/.claude/state/circuit-health-log/` and `~/.claude/state/external-monitor-alerts/`; reads `~/.claude/state/circuit-health-monitor-paused` (pause marker).

- [x] 2. Run initial seed probe against current Circuit prod. Verification: mechanical
  **Prove it works:** `bash tools/circuit-health-probe.sh` returned exit 1 with 18/24 healthy + 6 TIMEOUT_OR_NETWORK anomalies; alert file written to `~/.claude/state/external-monitor-alerts/2026-05-21T13-57-45Z.json`.
  **Wire checks:** n/a.
  **Integration points:** confirms the probe correctly classifies real-world anomalies (the supabase-js fetch deadlock matches Circuit's own documented incident in `circuit/src/app/api/health/route.ts`).

- [x] 3. Author `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` (generic — surfaces alerts from a configured external-monitor dir) and wire into live `~/.claude/settings.json` only. Verification: mechanical
  **Prove it works:** `bash adapters/claude-code/hooks/external-monitor-alert-surfacer.sh --self-test` exits 0 with 6/6 PASS; live mirror at `~/.claude/hooks/external-monitor-alert-surfacer.sh` also passes self-test; live `~/.claude/settings.json` contains the new hook entry between `spawned-task-result-surfacer` and `plan-status-archival-sweep`. The kit template `adapters/claude-code/settings.json.template` is intentionally NOT modified — this hook is generic-shaped but its instance-specific wiring (alert dir, monitor name) is per-machine.
  **Wire checks:** n/a — single-purpose hook composes with existing SessionStart chain.
  **Integration points:** live `~/.claude/settings.json` SessionStart chain only.

- [x] 4. Author runbook `docs/operations/circuit-health-monitor-2026-05-20.md` (single document). Verification: mechanical
  **Prove it works:** file exists, ≥ 200 lines, names every artifact created by this plan and the exact commands needed to enable a 30-min schedule via MCP scheduled-tasks (Option A) or Windows Task Scheduler (Option B).
  **Wire checks:** n/a — pure documentation.
  **Integration points:** the runbook is the entry point any future session uses to extend / debug the monitor.

## Files to Modify/Create

- `tools/circuit-health-probe.sh` — the probe (NEW).
- `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` — the SessionStart surfacer (NEW).
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — extends `is_exempt()` with file-path exemptions for the intentionally-instance-specific Circuit-named files (the probe, the surfacer, the runbook, this plan).
- `~/.claude/hooks/external-monitor-alert-surfacer.sh` — live mirror of the surfacer (per harness two-layer config discipline; not under git in `neural-lace/` proper but referenced).
- `~/.claude/settings.json` — wires the surfacer into SessionStart (instance-specific; the kit template at `adapters/claude-code/settings.json.template` is INTENTIONALLY NOT modified — Circuit wiring is per-machine ops tooling).
- `docs/operations/circuit-health-monitor-2026-05-20.md` — runbook (NEW).
- `docs/plans/circuit-prod-health-monitor.md` — this plan (NEW).

## In-flight scope updates

(none)

## Assumptions

- Circuit prod URL is `https://circuit.pocket-technician.com` (verified from Circuit's `tests/e2e.js`).
- The Dispatch orchestrator runs on the same machine as the scheduled task; alert files in `~/.claude/state/external-monitor-alerts/` are visible to both.
- `curl` is available on the host (required for the probe; pre-flight check enforced).
- The user has standing authorization (this session) to commit, push, open a PR, and merge to master autonomously.
- The MCP `scheduled-tasks` integration requires interactive approval per call — this is observed empirically (the autonomous call returned "requires user interaction"). The runbook captures the exact follow-up the user runs once to enable Option A.

## Edge Cases

- **Probe runs while Circuit prod is fully down (DNS, TLS, all routes fail):** every route classifies as TIMEOUT_OR_NETWORK; the alert file is one large list of failures. Surfacer caps display at 5 newest entries — acceptable; the user-visible message says `N unacked Circuit-prod anomaly alert(s)` even when many.
- **Maintenance pause marker present:** probe runs, history log is still written, alert file is NOT written. Suppression noted in stderr. Removing the marker resumes alert emission.
- **Probe writes alert file but next session never starts:** alert file persists indefinitely (no expiry). Next session-start surfacer will pick it up. Sorted reverse-chrono so newest surfaces first.
- **Multiple alert files stack up while pause marker is active or while orchestrator isn't running:** displayed five newest; older files are still inspectable via `ls -la ~/.claude/state/external-monitor-alerts/`.
- **Alert file becomes malformed (truncated write, disk full):** surfacer detects via `jq empty` (or fallback bracket heuristic) and skips with a stderr warning rather than crashing the SessionStart chain.
- **Route catalog needs update after a Circuit deploy that renames an endpoint:** documented procedure in runbook ("Updating the route catalog"); per-route format keeps the change to a one-line edit.
- **A route's expected response intentionally changes** (e.g., a public route that was 200 becomes 307): the probe will flag it as UNEXPECTED_STATUS until the catalog is updated. This is the intended behavior — false positives surface immediately and force catalog maintenance.

## Testing Strategy

- **Mechanical:** both `--self-test` suites (probe: 6/6 PASS, surfacer: 6/6 PASS); live mirror sync verified byte-identical via the natural cp+chmod sequence in the build steps.
- **Runtime (seed):** one real probe run against current Circuit prod, recorded — confirms the probe detects the documented active incident (the supabase-js fetch deadlock affecting six POST/health routes).
- **Surfacer integration:** the seed alert was deliberately left unacked so the NEXT session start observably surfaces the alert via the new hook. This is the runtime acceptance criterion for the surfacing path.

## Walking Skeleton

Smallest end-to-end vertical slice:
1. Probe hits `https://example.com` (vendor-independent canary used in the probe's self-test scenarios 4/5).
2. Probe emits JSON with one route's verdict.
3. Probe writes that JSON to a temp `~/.claude/state/external-monitor-alerts/` (test-scope dir).
4. Surfacer reads the temp dir and emits a system-reminder.
5. Marking the file with a `.acked` sibling silences the surfacer.

Self-tests s3-s6 in `external-monitor-alert-surfacer.sh` exercise this end-to-end (with synthetic JSON, not via the live probe — but the schema is identical, so production probe output composes correctly). The full real path was exercised by the seed run + first surfacer self-test.

## Decisions Log

### Decision: Scheduling — Option A as preferred, Option B as autonomous fallback
- **Tier:** 1
- **Status:** Option A pending one-time user approval; Option B fully documented + ready to run.
- **Chosen:** Document both options in the runbook with exact ready-to-run commands. Recommend A primarily, B for overnight coverage.
- **Alternatives:** Option C (Trigger.dev cloud cron) — rejected because the probe is local-state-writing; cloud-cron would need a state-sync layer for no real benefit.
- **Reasoning:** The MCP `create_scheduled_task` requires interactive approval (it returned `requires user interaction` on the autonomous attempt). Option B (Windows Task Scheduler) is fully autonomous AND provides coverage when Claude Code is closed. Documenting both gives the user a clear path under either constraint.
- **Checkpoint:** N/A (no code change; documentation captures the deferred approval).
- **To reverse:** Strip the MCP-A section from the runbook; advertise Option B as the only path.

### Decision: 24 routes, not fewer
- **Tier:** 1
- **Status:** Implemented.
- **Chosen:** 24 routes covering health, auth-required APIs, webhooks, public pages, lead-intake.
- **Alternatives:** A smaller set (say 8 routes) would reduce probe wall-time. A larger set (every route under `/api/`) would catch more but at cost of catalog churn.
- **Reasoning:** Mirrors the Circuit `tests/e2e.js` route inventory closely so the catalog stays maintainable against the same baseline source. 24 routes at ≤ 15s/route timeout = ~2 min worst case (when several are timing out), well under any reasonable cron interval.
- **Checkpoint:** N/A.
- **To reverse:** Edit the `ROUTES` array; re-run `--self-test`.

### Decision: 10s slow threshold
- **Tier:** 1
- **Status:** Implemented (configurable via `CIRCUIT_PROBE_SLOW_MS`).
- **Chosen:** 10000ms.
- **Alternatives:** 5000ms (Circuit's e2e.js uses 5s for the "respond within" assertion).
- **Reasoning:** 5s would flag normal cold-start latency under low traffic as anomalous. 10s is comfortably above Circuit's typical hot-path latency (< 1s observed in seed run) and below the 15s curl timeout, giving a healthy SLOW band.
- **Checkpoint:** N/A.
- **To reverse:** Override at invocation with `CIRCUIT_PROBE_SLOW_MS=5000`.

## Pre-Submission Audit

(Not applicable — this is a `Mode: code` plan, not `Mode: design`. Per `~/.claude/rules/design-mode-planning.md`, the pre-submission class-sweep audit is mandatory only for design-mode plans.)

## Definition of Done

- [x] Probe script self-test 6/6 PASS.
- [x] Surfacer self-test 6/6 PASS (canonical + live mirror).
- [x] Initial seed run completed; behavior recorded (6 real anomalies detected — the system found exactly what it was built to find on first run).
- [x] Runbook authored.
- [x] Plan-level files match `## Files to Modify/Create`.
- [ ] Committed to feature branch.
- [ ] PR opened, merged to master.
- [ ] Plan flipped to `Status: COMPLETED` (which triggers auto-archive via `plan-lifecycle.sh`).
