# Harness Reliability Improvements — Deploy + Remote-State Verification

**Date:** 2026-05-21
**Author:** harness investigation (Misha-directed)
**Status:** PROPOSAL — open for discussion, no implementation in this session
**Companion audit:** `docs/reviews/2026-05-21-harness-deploy-verification-audit.md`
**Friction-reflexion class:** all six mechanisms below are "things I encountered in real failures, not improvements I went hunting for" (per `~/.claude/rules/friction-reflexion.md`).

---

## 1. The gap, in one sentence

The harness has no mechanism that connects an orchestrator action (push, merge, deploy, open-PR) to the remote-state consequence of that action (CI green/red, deploy succeeded/failed, smoke routes 2xx/5xx). Between turns, GitHub and Vercel are invisible. This proposal closes that gap.

---

## 2. The six proposed mechanisms

Each mechanism is sized + ranked. Building all six gives full coverage. Building **A + B + C** alone closes ~80% of the failure pattern from the audit.

### A. Post-push CI watcher

**Trigger:** PostToolUse Bash hook matching `git push origin ...` (or any push that lands a feature branch / master).

**Behavior:**
1. After `git push` returns 0, parse the pushed ref + SHA.
2. Wait ~10 seconds for GitHub Actions to register the push.
3. Invoke `gh run list --branch <branch> --limit 5 --json status,conclusion,name,databaseId,createdAt` and find runs whose `createdAt` > push-time.
4. For each run, invoke `gh run watch <id> --exit-status --interval 30` in the background (or poll synchronously up to a 10-min cap).
5. On completion: if `conclusion != success` for ANY run, write an alert JSON to `~/.claude/state/external-monitor-alerts/<ts>-ci-fail-<branch>.json` with `{branch, sha, run_id, run_name, conclusion, url}`. The existing `external-monitor-alert-surfacer.sh` SessionStart hook will surface it on the next session.
6. On success: optionally write a `.ack` marker so the surfacer ignores it.

**Implementation sketch:**
- `adapters/claude-code/hooks/post-push-ci-watcher.sh` — PostToolUse Bash hook. Parses tool input + output. Spawns a background `nohup` subprocess that does the wait + watch + write so the hook returns immediately (the orchestrator does not block).
- Self-test: synthetic `gh run list` JSON fixture; the hook's parsing logic asserts it correctly classifies success / failure / in-progress.
- Bypass: `POST_PUSH_CI_WATCHER_DISABLE=1` for harness-dev sessions where the hook self-triggers.

**Estimated effort:** 4-6 hours (hook + background subprocess wiring + self-test + wiring into `settings.json.template`). Backgrounded child process is the only mildly tricky part.

**Unilaterally buildable by orchestrator?** Yes. No external account setup needed; `gh` is already authenticated.

**What it catches:** §2.1 (PR #19 CI fail unnoticed), §2.6 (PRs sitting with red CI). Does NOT catch deploy failures unless those manifest as a failed GitHub Actions check (Vercel's auto-deploy may or may not — depends on project config).

**Limitations:**
- Backgrounded subprocess on Windows Git Bash may not survive shell exit; needs `setsid` or PowerShell `Start-Process` equivalent. Worst case: synchronous wait up to 10 min, blocking the orchestrator for that long after push (acceptable when push is the last action; problematic when followed by more work).
- Multi-repo: the hook fires for whatever repo the orchestrator's cwd is in; cross-repo would need a different trigger.

---

### B. Post-merge prod-smoke probe

**Trigger:** PostToolUse Bash hook matching `gh pr merge ... --merge` / `--squash` / `--rebase` (any merge command).

**Behavior:**
1. After `gh pr merge` returns 0, read `<repo>/.claude/deploy-config.json` (new file, per-repo) which declares:
   - `deploy_target_url` (e.g., `https://<your-app-domain>`)
   - `smoke_routes`: array of `{method, path, expected_statuses, label}` (mirrors the existing prod-health-probe's `ROUTES` array format)
   - `smoke_delay_seconds` (default 180 — give Vercel ~3 min to build + promote)
   - `smoke_timeout_seconds` (default 600 — give up after 10 min)
2. Schedule a background subprocess that sleeps `smoke_delay_seconds`, then runs the same probe logic as the existing instance-specific prod-health probe against `deploy_target_url` + routes.
3. Write probe results to `~/.claude/state/deploy-probe-log/<ts>.json` (mirrors the existing instance-monitor log convention; per-monitor log dir).
4. If any route is unhealthy, write an alert JSON to `~/.claude/state/external-monitor-alerts/<ts>-deploy-fail-<repo>.json` with `{repo, merged_pr, sha, deploy_url, results}`. Surfacer presents on next session.
5. If config is missing for the repo, skip silently (downstream projects without deploy verification opt out by simply not creating the file).

**Implementation sketch:**
- `adapters/claude-code/hooks/post-merge-deploy-probe.sh` — PostToolUse Bash hook. Backgrounded subprocess.
- Reuses the existing instance-specific prod-health probe's engine logic at `tools/` (extract into a shared lib, parametrize the route list).
- Per-repo config at `<repo>/.claude/deploy-config.json` — generic shape, instance-specific contents.
- Self-test: mock `<repo>/.claude/deploy-config.json` with one healthy + one unhealthy synthetic route; assert correct alert generation.

**Estimated effort:** 6-8 hours (factor probe-engine, write the per-repo config schema, hook + background wiring + self-test). Extracting the probe engine to a reusable lib is the bulk.

**Unilaterally buildable by orchestrator?** Yes for the harness mechanism. **Requires Misha's input** for each downstream project to populate `<repo>/.claude/deploy-config.json` with the right `deploy_target_url` and smoke-route list. Per-project: ~15-30 min each.

**What it catches:** §2.2 (PR #304 Sentry — Vercel broke prod), §2.3 (PR #298 RBAC), and any future deploy that breaks user-observable routes.

**Limitations:**
- Smoke probe only catches what the route list covers; routes not in the list go unchecked.
- 3-min delay is a guess — could be too short (Vercel build sometimes takes longer) or too long (deploy already broken by the time we check). Tuneable per project.
- Unauthenticated probes only (matches the existing prod-health probe discipline) — can't catch logged-in-only regressions.

---

### C. Orchestrator turn-start digest (multi-repo PR-status sweep)

**Trigger:** SessionStart hook. Always runs.

**Behavior:**
1. Read `~/.claude/local/multi-repo-watch.json` (new file) which declares an allowlist of repos to monitor (e.g., `["<owner>/neural-lace", "<owner>/<project>", ...]`).
2. For each repo, run `gh pr list --repo <repo> --state open --author "@me" --json number,title,statusCheckRollup,headRefName,createdAt,url`.
3. For each open PR, compute a status:
   - **RED:** any check has `conclusion: "failure"` or `state: "FAILURE"`.
   - **PENDING:** any check is in-progress and PR is > 30 min old (probably stuck or rate-limited).
   - **STALE:** PR open > 24 hours with no recent commits (work was abandoned).
   - **GREEN:** all checks passed.
4. Emit a system-reminder block listing PRs with RED / PENDING / STALE status. GREEN PRs are silent.
5. Cap at 10 surfaced PRs to avoid flood.

**Implementation sketch:**
- `adapters/claude-code/hooks/multi-repo-pr-digest.sh` — SessionStart hook.
- Reads `~/.claude/local/multi-repo-watch.json` (per-machine; not in kit).
- Mirrors `external-monitor-alert-surfacer.sh` shape: silent when empty, exit 0, `--self-test` with fixture JSONs.
- Caches `gh pr list` results for 5 minutes at `~/.claude/state/multi-repo-pr-cache.json` to avoid hitting GitHub API on every session start (a single Dispatch turn = one session start; many starts per day).

**Estimated effort:** 4-5 hours (hook + cache + self-test + wiring). `gh pr list --json` returns everything needed; the hook just classifies + formats.

**Unilaterally buildable by orchestrator?** The mechanism — yes. **Requires Misha's input** to populate `~/.claude/local/multi-repo-watch.json` with the repos he wants tracked.

**What it catches:** §2.6 (PRs with red CI sitting unnoticed), partially §2.1 (would surface PR #19's red check on the next session start). Combined with (A), CI failures are caught both at push time (A) and on every subsequent session start (C) until acknowledged.

**Limitations:**
- Only catches PRs authored by the current `gh` user — won't see PRs opened by other accounts unless explicitly added.
- 5-min cache means a check that fails right after a session start won't surface until ~5 min later.

---

### D. Scheduled-task orchestrator heartbeat

**Trigger:** `scheduled-tasks` MCP cron, every 15 or 30 minutes.

**Behavior:**
1. A fresh ephemeral Claude Code session spawns on schedule.
2. The session prompt: "Check all repos in `~/.claude/local/multi-repo-watch.json`. For each open PR, report any failing CI checks or stalled deploys. Run smoke probes against deploy URLs from `deploy-config.json` files. Write alerts to `~/.claude/state/external-monitor-alerts/` and exit."
3. The session ends. The next interactive session sees any alerts via the existing surfacer.

**Implementation sketch:**
- One scheduled task created via `mcp__scheduled-tasks__create_scheduled_task` (requires user approval — the runbook for the existing prod-health-monitor instance has the canonical procedure under `docs/operations/`).
- The task's prompt is a self-contained checklist; the harness's existing primitives (`gh`, `curl`, the probe script) do all the work.
- Pause marker at `~/.claude/state/multi-repo-watch-paused` to silence during maintenance.

**Estimated effort:** 2 hours (write the task prompt + a pause marker convention + a runbook). The mechanism is just config + a prompt.

**Unilaterally buildable by orchestrator?** No — `scheduled-tasks` MCP requires explicit user approval to create. **Requires Misha's one-time approval.**

**What it catches:** anything (A), (B), and (C) would catch — but catches it even when no interactive session is running (overnight / weekend / desktop closed). This is the safety-net layer.

**Limitations:**
- Costs one ephemeral session per run (cheap, but counts against any model rate-limit budget).
- Alerts only surface on the next interactive session, not in real time — same latency story as the existing external-monitor pattern.
- The scheduled-task session must be authorized to invoke `gh` / `curl` / read `~/.claude/local/` — the existing per-machine auth handles this; no separate setup needed.

---

### E. GitHub Actions failure → webhook → file marker

**Trigger:** GitHub repository webhook (configured per-repo).

**Behavior:**
1. Configure each watched repo's webhook to POST `workflow_run` events to a small local HTTP endpoint (e.g., `http://localhost:7842/github-events`) running on Misha's machine. Or to a tunneled endpoint (ngrok / Cloudflare Tunnel) if reaching localhost from GitHub is impractical.
2. The local receiver script:
   - Verifies the webhook signature.
   - Filters for `workflow_run.completed` with `conclusion != success`.
   - Writes an alert JSON to `~/.claude/state/external-monitor-alerts/<ts>-gha-fail-<repo>.json`.
3. Existing surfacer presents on next session.

**Implementation sketch:**
- `adapters/claude-code/scripts/gha-webhook-receiver.sh` — long-running bash script (or a tiny Node / Deno HTTP server). Runs as a Windows service or daemon-equivalent.
- Per-repo webhook configuration via `gh api repos/<repo>/hooks` (one-time setup per repo).
- Secret-shared via `~/.claude/local/gha-webhook-secret.txt` (gitignored).

**Estimated effort:** 8-12 hours (writing the receiver + signature verification + Windows-service wrapping + per-repo configuration + ngrok / tunnel setup OR localhost-only with a documented limitation). The non-mechanism work (tunnel setup, GitHub UI clicks) is most of the time.

**Unilaterally buildable by orchestrator?** No. **Requires Misha's input** for:
- One-time tunnel setup OR explicit decision to run localhost-only (which limits webhooks to when his machine is on).
- Per-repo webhook configuration (each repo needs the webhook added with the secret).
- Windows-service installation (one-time admin action).

**What it catches:** GitHub Actions failures in real time (within seconds of the failure), independent of whether an interactive session is running. Strictly stronger than (A) for the CI-failure case, but only for repos with the webhook configured. (A) catches every push; (E) catches every CI failure but only after webhook setup.

**Limitations:**
- Requires running infrastructure (the receiver).
- Tunnel setup is friction.
- Webhook delivery can fail (GitHub retries, but bursts can be missed).

**Verdict:** consider deferring until A/B/C are exercised in practice. The real-time gain over (A)+(C) is modest unless overnight monitoring matters more than the audit suggests.

---

### F. Vercel deployment-status webhook → file marker

**Trigger:** Vercel deployment webhook (configured per-Vercel-project).

**Behavior:**
1. Configure Vercel project webhooks to POST `deployment.succeeded` / `deployment.error` events to the same local receiver as (E).
2. Receiver filters for `deployment.error` events and writes an alert JSON to `~/.claude/state/external-monitor-alerts/<ts>-vercel-fail-<project>.json` with build-log URL.
3. Surfacer presents on next session.

**Implementation sketch:**
- Reuses the receiver from (E).
- Vercel webhook configured via Vercel dashboard or `vercel webhooks add` CLI.
- Per-project; harmless to configure even on staging-only projects.

**Estimated effort:** 2-3 hours **on top of (E)**. The infrastructure is shared; only the per-event filtering + per-project webhook setup are new.

**Unilaterally buildable by orchestrator?** No. **Requires Misha's input** for per-project Vercel webhook setup.

**What it catches:** Vercel deploy failures in real time, independent of (B)'s smoke-probe delay. Strictly stronger than (B) for the build-failed case (catches a deploy that never even reached prod), but does NOT catch deploy-succeeded-but-broken-at-runtime cases (which B does).

**Verdict:** if (E) ships, (F) is a cheap add. Without (E), the infrastructure cost is too high for the marginal benefit over (B).

---

## 3. Ranking matrix

| # | Mechanism | Coverage gain | Effort | Misha-input | Unilateral? | Priority |
|---|---|---|---|---|---|---|
| A | Post-push CI watcher | High — catches every push's CI | 4-6h | None | Yes | **1** |
| B | Post-merge prod-smoke probe | High — catches deploy regressions | 6-8h + ~30min per project for config | Per-project config | Yes (mechanism); no (per-project content) | **2** |
| C | Orchestrator turn-start PR digest | High — catches everything between sessions | 4-5h | Multi-repo allowlist | Yes (mechanism); no (allowlist) | **3** |
| D | Scheduled-task heartbeat | Medium — overnight coverage | 2h | One-time MCP approval | No (needs approval) | **4** |
| E | GitHub Actions webhook receiver | Medium — real-time CI alerts | 8-12h | Tunnel + per-repo webhooks + service install | No | 5 |
| F | Vercel webhook receiver | Medium — real-time deploy alerts | 2-3h on top of E | Per-project Vercel webhooks | No | 6 |

**Effort total for A+B+C:** ~14-19 hours of harness work + ~30 min per downstream project for config.
**Effort total for all six:** ~26-36 hours + significant per-project / per-machine setup.

---

## 4. Recommended priority — build A + B + C now

If only 2-3 mechanisms can be built, build **A + B + C**.

### Why this combination

- **A (post-push CI watcher)** catches the most common failure shape — push lands, CI fails, orchestrator never noticed. Fires every push. Zero per-project config.
- **B (post-merge smoke probe)** catches the most expensive failure shape — merge lands, prod breaks, users hit broken site for hours. Fires every merge. Per-project config opt-in keeps it scoped.
- **C (turn-start PR digest)** catches everything that fell through A or B because the alert wasn't seen, plus PRs from prior sessions. Fires every SessionStart. Per-machine config opt-in.

Together they form **three independent observation channels** at three different lifecycle points (push, merge, session-start). A failure has to escape all three to stay invisible.

### Why defer D, E, F

- **D (scheduled heartbeat)** is overnight coverage. It is a strict subset of "what A + B + C would have caught if there were a session running" — useful only when there isn't one. Defer until A+B+C are battle-tested.
- **E (GitHub webhook)** has high infrastructure cost (tunnel, service, per-repo setup) for marginal benefit over A + C. The "real-time vs next-session-start" gain matters only for overnight failures, and D is the cheaper coverage for that case.
- **F (Vercel webhook)** is a cheap add on top of E. Without E, the standalone cost is roughly the same as E. Defer alongside E.

### Build order within A + B + C

1. **A first.** It is the simplest mechanism, unlocks immediate value, and the background-subprocess work is reusable for B. Standalone testable; no per-project config needed.
2. **B next.** Builds on A's PostToolUse-with-background-subprocess pattern; extracts the probe engine into a reusable lib that downstream `deploy-config.json` consumes.
3. **C third.** Different lifecycle position (SessionStart vs PostToolUse), so it does not block on A/B. Could go in parallel with B if dispatched as separate plan tasks.

---

## 5. Cross-cutting design decisions to surface to Misha

These decisions affect all three mechanisms; getting them right once avoids rework:

### 5.1 Alert directory naming

Current: `~/.claude/state/external-monitor-alerts/` is shared between the existing prod-health probe and any future external monitor. Should A's "CI-failed" alerts share that directory (clean — one surfacer) or have their own (cleaner — separate ack lifecycle, per-source filtering)?

**Recommendation:** share the directory but use filename-prefix discipline (`ci-fail-<...>.json`, `deploy-fail-<...>.json`, `vercel-fail-<...>.json`, `health-anomaly-<...>.json`). Lets the surfacer present a unified view; ack is per-file regardless of source. **Auto-applicable if uncontested.**

### 5.2 Background subprocess on Windows Git Bash

`nohup foo &` works on Windows Git Bash but the child process is tied to the parent shell session by default; closing the terminal kills it. For overnight watching (A waits up to 10 min, B waits up to ~15 min), the orchestrator session might end before the watcher completes.

**Options:**
- **Synchronous wait inside the hook** — orchestrator blocks for N min after push. Cleanest semantics; blocks the session.
- **Backgrounded via `setsid` / PowerShell `Start-Process`** — fire-and-forget; survives shell exit. Trickier on Windows.
- **External daemon** — overkill at this scale.

**Recommendation:** start with synchronous wait (10-min cap for A, 15-min cap for B). Most pushes/merges happen at the END of a session, where blocking 10 min is acceptable (orchestrator wraps up after). If this becomes painful, upgrade to backgrounded later. **Decision needed from Misha — synchronous-block vs background-subprocess as v1 choice.**

### 5.3 Per-project deploy-config schema

(B) needs per-project route lists. Schema sketch:

```json
{
  "deploy_target_url": "https://app.example.com",
  "smoke_delay_seconds": 180,
  "smoke_timeout_seconds": 600,
  "smoke_routes": [
    {"method": "GET", "path": "/", "expected_statuses": [200, 302], "label": "root"},
    {"method": "GET", "path": "/api/health", "expected_statuses": [200, 503], "label": "health"}
  ]
}
```

This mirrors the existing prod-health probe's `ROUTES` array structure. **Recommendation:** lift to a shared schema at `adapters/claude-code/schemas/deploy-config.schema.json` so the existing probe + B + any future probe all read the same shape. **Auto-applicable if uncontested.**

### 5.4 What happens when A's CI-watch times out at 10 min

CI sometimes takes > 10 min (slow tests, queue delays). If the watcher hits its cap with checks still in-progress, options:
- Write a `ci-pending-<...>.json` alert ("still in progress at timeout — check manually"). Surfacer presents it.
- Write nothing — silence is fine if checks are still healthy.
- Extend the cap to 30 min.

**Recommendation:** write `ci-pending-<...>.json` with the run URLs so the next session can `gh run watch` them manually. Surfaces the unknown rather than swallowing it. **Auto-applicable if uncontested.**

---

## 6. What this proposal explicitly does NOT cover

- **Session-killed detection** (§2.5 in the audit). Different mechanism — SessionStart hook compares prior session's transcript last-message against expected `DONE:`/`PAUSING:`/`BLOCKED:` marker. Worth shipping but orthogonal to deploy verification. Filed as a candidate for a separate proposal.
- **DONE: semantic check** (§2.4). Extension of `continuation-enforcer.sh`. Worth doing; orthogonal mechanism, lives in the Stop hook not the deploy pipeline. Filed as a candidate for a separate proposal.
- **Cross-machine alert surfacing** (Misha works on multiple machines). The external-monitor pattern is per-machine. Cross-machine sync is a future concern; defer.

---

## 7. Asks for Misha (before any of this is built)

Per `~/.claude/rules/friction-reflexion.md` discuss-before-build:

1. **Approve A + B + C as the priority set** (or redirect — different ranking, different combination).
2. **Decide synchronous-block vs background-subprocess for v1** (§5.2).
3. **Confirm alert directory + schema conventions** (§5.1, §5.3) — both have safe defaults marked "auto-applicable if uncontested," but Misha may want to inspect the schema.
4. **Provide multi-repo allowlist for C** when ready (no rush; the mechanism works with an empty list — just silently does nothing).
5. **Per-project: identify the first 1-2 downstream projects** where B's `deploy-config.json` should land first (Misha names them — the prod-health-monitor's existing target is the obvious candidate).
6. **Decide whether D should be built right after A/B/C** (overnight coverage gain vs incremental complexity) or deferred indefinitely.

Items 5 and 6 are deferrable until A/B/C are built; items 1-4 are on the critical path.

---

## 8. Cross-references

- **Audit companion:** `docs/reviews/2026-05-21-harness-deploy-verification-audit.md`
- **Existing external-monitor surfacer (the canonical surfacing primitive):** `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh`
- **Existing probe (the engine to extract):** the instance-specific prod-health probe at `tools/` (file path is instance-named per the harness-hygiene instance-tooling boundary; treat as the canonical reference for the probe-engine shape)
- **Existing automation-mode config (where deploy-class commands are classified):** `adapters/claude-code/hooks/automation-mode-gate.sh`
- **Existing continuation enforcer (where semantic-DONE would land — out of scope here):** `adapters/claude-code/hooks/continuation-enforcer.sh`
- **`scheduled-tasks` MCP runbook precedent:** the prod-health-monitor runbook under `docs/operations/` (instance-specific filename per harness-hygiene) — "Enabling the schedule" Options A/B/C
- **Pattern for "next session, here's what happened":** `adapters/claude-code/hooks/spawned-task-result-surfacer.sh` + `adapters/claude-code/rules/spawn-task-report-back.md`
- **Friction-reflexion (why this proposal exists at all):** `adapters/claude-code/rules/friction-reflexion.md`
