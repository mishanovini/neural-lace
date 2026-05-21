# Circuit Production Health Monitor — Runbook

**Date:** 2026-05-20 (initial build); 2026-05-21 (initial seed run)
**Owner:** harness-maintenance (Misha)
**Target:** `https://circuit.pocket-technician.com`
**Status:** ACTIVE — probe deployed, scheduler wiring pending user approval (see "Enabling the schedule")

## Summary

A self-monitoring health checker that probes ~24 critical Circuit-prod routes
every 30 minutes, writes anomaly markers to a known directory, and surfaces
them to the next interactive Dispatch-orchestrator session via a
`SessionStart` hook. Goal: prod regressions get noticed automatically the
moment they happen, not "later when someone tries the feature."

Components:

| File | Role |
|---|---|
| `tools/circuit-health-probe.sh` | The probe. Fires HTTP requests, classifies anomalies, writes alerts. |
| `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` | SessionStart hook. Reads alerts, emits a system-reminder block to the orchestrator. |
| `~/.claude/settings.json` (live, per-machine) | Wires the surfacer into the SessionStart chain. NOT mirrored back to `settings.json.template` — this is instance-specific tooling and the kit template stays generic. |
| `~/.claude/state/circuit-health-log/<ts>.json` | Historical log of every probe run (healthy or not). |
| `~/.claude/state/external-monitor-alerts/<ts>.json` | Anomaly markers — surfaced until acknowledged. |
| `~/.claude/state/circuit-health-monitor-paused` | Optional pause marker (suppresses alert emission during maintenance). |
| Scheduled task (cron `*/30 * * * *`) | Invokes the probe every 30 min. See "Enabling the schedule" below. |

## What's monitored

24 critical Circuit-prod routes, declared inline in `tools/circuit-health-probe.sh`
(the `ROUTES` array). Each route declares: METHOD, PATH, EXPECTED-STATUS-CODES
(comma-separated), TIMEOUT (seconds), LABEL.

Categories and expected responses (mirrors `tests/e2e.js` conventions in the
Circuit repo):

| Category | Routes | Expected | Why |
|---|---|---|---|
| Public/health | `/api/health`, `/`, `/login`, `/signup` | 200 (or 503 degraded for `/api/health`); root and `/signup` may redirect | These are the only routes a logged-out human should be able to reach without being bounced. |
| Auth-required API | `/api/auth/session`, `/api/booking`, `/api/campaigns`, `/api/reps`, `/api/templates`, `/api/costs`, `/api/dashboard`, `/api/conversations`, `/api/analytics/funnel`, `/api/alerts`, `/api/notifications`, `/api/contacts/<id>`, `/api/settings/usage` | **307 or 302** (middleware redirect to `/login`) | An unauthenticated probe should NEVER see 200 from these (would mean data leak); should NEVER see 5xx (would mean the route's auth guard crashed); should NEVER see 404 (would mean the route was deleted accidentally). |
| Webhooks | `/api/webhooks/retell`, `/api/webhooks/resend` POST | **401** (signature missing) | Webhook routes that reach handler code and reject by auth = healthy. 5xx means handler crashed; 200 without a signature would mean signature check is disabled (security regression). |
| Webhook (Twilio) | `/api/webhooks/twilio` POST | **200** (empty TwiML) or **403** | Twilio is special: the route returns 200 with empty TwiML to prevent Twilio's retry storm even when the signature fails. 200 + `text/xml` Content-Type is healthy. |
| Auth-required pages | `/dashboard`, `/contacts`, `/settings` | **307 or 302** to `/login` | Same as auth-required APIs — unauth user must be bounced. |
| Public lead intake | `/api/leads` POST (empty body) | **400** (validation) or **401** (webhook-secret) | The route should reach validation; either response shape is acceptable. 500 = route is broken. |

### Anomaly verdicts the probe emits

- `HEALTHY` — response status was in the expected list AND elapsed ≤ 10s.
- `HTTP_5XX` — server returned 5xx. Page/handler is broken.
- `UNEXPECTED_STATUS` — got some status not in the expected list (e.g., 404 on a route that should redirect; 200 on a route that should reject).
- `TIMEOUT_OR_NETWORK` — curl timed out (default 15s) or could not connect. Status code reported as `000`.
- `SLOW` — response was OK but took longer than `CIRCUIT_PROBE_SLOW_MS` (default 10000ms / 10 seconds).

Any non-`HEALTHY` verdict triggers an anomaly alert.

## How to read the logs

### History (every run, healthy or not)

```bash
ls -la ~/.claude/state/circuit-health-log/
cat ~/.claude/state/circuit-health-log/<timestamp>.json | jq .
```

Each file is the same JSON shape (schema version 1):

```json
{
  "schema_version": 1,
  "circuit_url": "https://circuit.pocket-technician.com",
  "started_at": "2026-05-21T13:55:46Z",
  "ended_at": "2026-05-21T13:57:44Z",
  "total_routes": 24,
  "healthy_count": 18,
  "anomaly_count": 6,
  "slow_threshold_ms": 10000,
  "results": [
    {
      "label": "api-health",
      "method": "GET",
      "path": "/api/health",
      "expected": "200,503",
      "status": "000",
      "elapsed_ms": 15480,
      "verdict": "TIMEOUT_OR_NETWORK",
      "failure_reason": "curl exit 28: Operation timed out after 15006 ms"
    }
    /* … one entry per route … */
  ]
}
```

### Active alerts (unacked anomalies)

```bash
ls -la ~/.claude/state/external-monitor-alerts/
```

An alert is a copy of the probe report at the moment the anomaly was detected.
Filenames are ISO timestamps. The surfacer reads alerts NOT covered by a
sibling `.acked` marker. To acknowledge:

```bash
touch ~/.claude/state/external-monitor-alerts/2026-05-21T13-57-45Z.json.acked
```

The next session start will no longer surface that alert.

## How the alert-file mechanism works (orchestrator integration)

1. **Probe runs.** Either via scheduled task or invoked manually. Probes all
   routes, emits a JSON report, exits 0 (healthy) or 1 (anomalies).
2. **On anomalies**, the probe writes the report to
   `~/.claude/state/external-monitor-alerts/<ISO-ts>.json`. (Always writes
   to `~/.claude/state/circuit-health-log/<ISO-ts>.json` regardless of verdict.)
3. **Next orchestrator session starts.** The `external-monitor-alert-surfacer.sh`
   SessionStart hook (wired in `~/.claude/settings.json`) runs.
4. **Surfacer emits a `<system-reminder>` block** listing up to 5 newest unacked
   alerts with: timestamp, anomaly count, route list with per-route
   verdict/status/elapsed/failure_reason.
5. **Orchestrator triages.** Three actions:
   - **(a) Investigate and fix** — diagnose the regression, open a fix branch in
     the Circuit repo. After the fix lands and a fresh probe confirms healthy,
     `touch <file>.acked` to dismiss.
   - **(b) Acknowledge as known** — if the regression is already tracked in
     `docs/findings.md` or a Circuit-side incident doc, `touch <file>.acked`.
     The alert no longer surfaces but the file remains for audit.
   - **(c) Pause monitoring during maintenance** — `touch
     ~/.claude/state/circuit-health-monitor-paused`. Probe still runs and logs
     history, but emits no new alert files. Remove the marker to resume.

### Why this composes with the orchestrator

The surfacer fires at SessionStart, BEFORE the orchestrator reads any other
context. The system-reminder block is one of the very first things the
orchestrator sees — alongside settings-divergence, pending-discoveries, etc.
The pattern mirrors `spawned-task-result-surfacer.sh` (which has been in
production since Phase 1d). Multi-alert flooding is capped at 5 visible
newest; the orchestrator can list the directory directly if more context is
needed.

## Enabling the schedule

Two options. Option A is the user's preferred path (per task spec); Option B
is the autonomous-compatible fallback (works without interactive approval).

### Option A — `scheduled-tasks` MCP (preferred, requires one user approval)

This is the cleanest integration: the cron task is a fresh ephemeral Claude
session that invokes the probe + reports succinctly. Lives alongside other
scheduled tasks in `~/.claude/scheduled-tasks/`.

**Why this couldn't be created autonomously in the initial build:** the MCP
`create_scheduled_task` tool requires interactive user approval (the runtime
returned `This tool requires user interaction and is unavailable in
unsupervised mode`).

**To enable, approve this exact call** (Misha pastes this into the next
interactive Claude Code session; the MCP prompt confirms the schedule once
and the task is then permanent until disabled):

> Create a scheduled task with these parameters:
> - `taskId`: `circuit-prod-health-probe`
> - `description`: `Probes Circuit prod every 30 min; writes anomaly markers picked up by the orchestrator surfacer.`
> - `cronExpression`: `*/30 * * * *` (every 30 minutes, local time)
> - `notifyOnCompletion`: `false`
> - `prompt`: see exact text below

The prompt to paste (verbatim — fully self-contained because each cron run is
a fresh session with no memory):

```
You are the Circuit-prod health-probe scheduled task.

YOUR ONE JOB: invoke the probe script. Do not investigate failures, do not
start fix work, do not narrate. The probe writes alert markers; the next
interactive orchestrator session will see them via the SessionStart surfacer.

Steps (perform all of them, do nothing else):

1. Run the probe (no arguments — defaults are correct):
   bash ~/claude-projects/neural-lace/tools/circuit-health-probe.sh --quiet

2. Read the exit code:
   - exit 0 → all routes healthy. Report ONE line:
     [circuit-health-probe] all routes healthy at <ISO timestamp>
   - exit 1 → anomalies detected. The probe has already written the alert
     marker. Report:
     [circuit-health-probe] anomaly detected — N/M routes anomalous; alert
     written to ~/.claude/state/external-monitor-alerts/<filename>.json
     Do NOT try to diagnose or fix. The next interactive session's
     orchestrator surfacer will pick it up and triage.
   - exit 2 → probe itself is broken. Report the failure with the script's
     stderr. Do not retry.

3. Stop. End the turn with the DONE marker:
   DONE: <one-line health summary>

Maintenance pause: if ~/.claude/state/circuit-health-monitor-paused exists,
the probe still runs but suppresses alert emission — your report should say
(paused — alerts suppressed) in that case.

Do NOT:
- Open browsers, tail logs, or read Circuit's source.
- Edit any plan files or backlog entries.
- Run any other commands.
- Create or modify any other files (the probe handles its own logging + alert files).

Runbook: ~/claude-projects/neural-lace/docs/operations/circuit-health-monitor-2026-05-20.md.
```

After approval, verify it landed via `mcp__scheduled-tasks__list_scheduled_tasks` —
look for `circuit-prod-health-probe` with `nextRunAt` populated.

**Note on app-closed behavior:** scheduled tasks only fire while Claude Code
is running. If the app is closed when a 30-min slot fires, the task runs on
next launch. For continuous monitoring while the desktop is closed, prefer
Option B.

### Option B — Windows Task Scheduler (fully autonomous, no Claude session)

The probe is a self-contained bash script — it can run from Windows Task
Scheduler without Claude Code being open. This gives 24/7 coverage but the
alert surfaces only when the orchestrator next starts a session.

**To enable**, run from an elevated PowerShell prompt on Misha's machine:

```powershell
$action  = New-ScheduledTaskAction -Execute "C:\Program Files\Git\bin\bash.exe" `
           -Argument "-l -c '~/claude-projects/neural-lace/tools/circuit-health-probe.sh --quiet >/dev/null'"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
           -RepetitionInterval (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName "CircuitHealthProbe" `
                       -Action $action -Trigger $trigger -Principal $principal `
                       -Description "Circuit prod health probe every 30 min — neural-lace tools/circuit-health-probe.sh"
```

Verify with `Get-ScheduledTask -TaskName CircuitHealthProbe`.

To remove: `Unregister-ScheduledTask -TaskName CircuitHealthProbe -Confirm:$false`.

### Option C — Trigger.dev or other cloud cron (not chosen)

The probe would have to be wrapped in an HTTP endpoint (Trigger.dev jobs run
on Trigger's infrastructure, not your laptop) and the anomaly alert files
would need to be uploaded somewhere accessible to the surfacer. Adds two
moving parts (HTTP wrapper + remote-state sync) for no real benefit over A
or B. Rejected.

### Recommendation

- For continuous monitoring during the workday and best orchestrator
  integration: **Option A**.
- For overnight / weekend monitoring while Claude Code is closed: **Option B**.
- Both can coexist — Option A drives most runs; Option B is the safety net.
  Running them both at slightly offset cadences (B at `:05` and `:35`, A at
  `:00` and `:30`) gives 15-minute effective resolution at zero extra cost.

## How to silence the monitor during maintenance

```bash
touch ~/.claude/state/circuit-health-monitor-paused
```

This causes the probe to:
- Still run on schedule.
- Still log every result to `~/.claude/state/circuit-health-log/`.
- **NOT** write any new files to `~/.claude/state/external-monitor-alerts/`.

So you keep the audit trail of "what would have alerted" without the surfacer
flooding session starts during a known-bad window. Remove the marker to
resume:

```bash
rm ~/.claude/state/circuit-health-monitor-paused
```

## Updating the route catalog

The route catalog is a bash array near the top of
`tools/circuit-health-probe.sh`. To add a route:

```bash
ROUTES=(
  …existing entries…
  "GET|/api/new-route|307,302|15|new-route-label"   # ← new line
)
```

Format: `METHOD|PATH|EXPECTED-STATUS-CODES|TIMEOUT-SECONDS|LABEL`.

- METHOD: `GET` or `POST`. (`PUT`/`DELETE` would need a small extension in
  `probe_one`.)
- PATH: starts with `/`. Include query string if needed.
- EXPECTED-STATUS-CODES: comma-separated list. Any of these = HEALTHY.
- TIMEOUT-SECONDS: per-request curl timeout. Default 15 is fine.
- LABEL: kebab-case, ≤ 30 chars, unique. Used in JSON output and surfacer.

For POST routes with bodies, extend `post_body_for()` to return the right
content-type and body bytes (current entries cover the existing webhooks +
`/api/leads`).

After editing, re-run `bash tools/circuit-health-probe.sh --self-test` and a
single manual probe (`bash tools/circuit-health-probe.sh | jq .`) to confirm
the new route's expected codes are right against current prod.

### How to choose EXPECTED codes for a new route

Look at the Circuit `tests/e2e.js` layer the route belongs to:

- Layer 1 (public/health): probably `200` (or `200,503` for health-style routes).
- Layer 2 (auth-required API): always `307,302`.
- Layer 3 (webhooks): `401` for handler-rejects-signature; `200,403` for Twilio.
- Layer 4 (pages): `200` for public pages, `307,302` for auth-required.

When in doubt, run the route manually first and lock in what you see TODAY
as the expected baseline.

## Initial seed run (2026-05-21)

The probe was executed against current prod (`https://circuit.pocket-technician.com`)
immediately after authoring. Result:

```
total_routes: 24
healthy_count: 18
anomaly_count: 6
```

The probe detected **6 unhealthy routes**, all `TIMEOUT_OR_NETWORK` (15s
timeout, status `000`):

1. `GET /api/health`
2. `GET /api/auth/session`
3. `POST /api/webhooks/retell`
4. `POST /api/webhooks/resend`
5. `POST /api/webhooks/twilio`
6. `POST /api/leads`

The first one (`/api/health`) matches the known active incident documented
inline in `circuit/src/app/api/health/route.ts`:

> Incident 2026-05-18: route handlers WITHOUT these directives hang on the
> supabase-js fetch in the current Vercel/Next runtime (Next's fetch-cache /
> instrumentation wrapper deadlocking with supabase-js).

The other five are the same shape — POST handlers that initialize Supabase
clients before doing their work. This is the EXACT regression-class the
monitor was built to detect: the user mentioned "the orchestrator stops
missing them" and indeed it had been missing them.

**The seed alert is at** `~/.claude/state/external-monitor-alerts/2026-05-21T13-57-45Z.json`.
This was deliberately left UNACKED for this PR so the orchestrator-side
surfacing path could be observed once on the next session — and so the
record of "the monitor caught this on its first run" is visible. Once you've
seen the surfacing happen, ack it (or fix the regression in Circuit first).

## Maintenance + audit checklist (suggested cadence)

- **Weekly:** scan `~/.claude/state/external-monitor-alerts/` for unacked
  files; ack stale ones; review history log for slow-route trends.
- **After every Circuit deploy:** run the probe manually once
  (`bash tools/circuit-health-probe.sh`) before walking away — catches
  deploy regressions before the next 30-min cron tick.
- **After every Circuit route addition/removal/rename:** update the `ROUTES`
  array in `tools/circuit-health-probe.sh`. Re-run `--self-test` + a manual
  probe.
- **If the probe itself starts misbehaving** (false positives, false
  negatives): `bash tools/circuit-health-probe.sh --self-test` first; if
  self-test passes, the catalog needs tuning. If self-test fails, the
  script regressed — git blame to find the offending commit.

## File index

| Path | Purpose |
|---|---|
| `tools/circuit-health-probe.sh` | The probe + its self-test |
| `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh` | SessionStart surfacer (canonical in neural-lace) |
| `~/.claude/settings.json` | Wires the surfacer into SessionStart (instance-specific; kit template intentionally NOT modified) |
| `~/.claude/hooks/external-monitor-alert-surfacer.sh` | Live mirror of the surfacer |
| `~/.claude/state/circuit-health-log/` | History (always written) |
| `~/.claude/state/external-monitor-alerts/` | Active alerts (consumed by surfacer) |
| `~/.claude/state/circuit-health-monitor-paused` | Optional pause marker |
| This file | The runbook |

## Failure modes the probe does NOT catch

Honest list of gaps — useful when triaging "the monitor said healthy but X is
broken":

- **Auth-flow regressions where unauth probes return correct redirects but
  authenticated traffic breaks.** The probe runs unauthenticated; it cannot
  detect a regression that's exclusively in the post-auth path. Mitigation:
  Circuit's own internal monitoring + the user-observable failure path.
- **Data-correctness regressions.** A route that returns 200 with the wrong
  body is "healthy" to the probe. Mitigation: dedicated integration tests
  inside the Circuit repo (`tests/api/*`).
- **Slow-but-under-threshold degradation.** A route consistently at 9.5s is
  not flagged (threshold is 10s). Mitigation: review history-log trends
  weekly; lower `CIRCUIT_PROBE_SLOW_MS` if needed.
- **Outages of Circuit's upstream services (Twilio, Retell, Resend, Resend
  webhooks)** that don't manifest as Circuit-side 5xx. The probe checks
  Circuit's *response*; if Circuit returns 401 cleanly even when the upstream
  is down, that looks healthy. Mitigation: per-upstream health checks
  (out of scope for this monitor).
- **Probes from one geographic origin.** The probe runs from wherever the
  scheduled task fires (Misha's machine, primarily). A regression that
  affects only a different region's edge would not be detected. Mitigation:
  acceptable for a single-developer ops loop.

## Change history

- 2026-05-21: initial build. 24 routes, 6 anomalies detected on first seed
  (active incident with supabase-js fetch in Vercel/Next runtime). Probe
  + surfacer self-tests both 6/6 PASS.
