# Harness Deploy-Verification Audit — 2026-05-21

**Author:** harness investigation (read-only)
**Trigger:** Misha asked "the harness is supposed to ensure that deploys actually succeed. can you validate that there's actually functionality in the harness for this? how do you think we can improve this?"
**Method:** read-only inventory of hooks / rules / scripts / workflows under `adapters/claude-code/` + `.github/`, cross-checked against this conversation's observed failure pattern.
**Scope:** what the harness mechanically does to ensure (a) CI succeeded after a push, (b) the production deploy went green after a merge, (c) regressions surface to the orchestrator session that caused them.

---

## TL;DR

**There is no active harness mechanism that watches CI or deploy status after a push or merge.** Every deploy-verification mechanism in the harness is either (a) a self-applied rule the agent is supposed to follow, (b) a local pre-push test receipt that doesn't touch the remote, or (c) a scheduled external probe that fires on its own cron cadence (independent of push/merge events). The Dispatch orchestrator's context between turns is never enriched with "PR #N now has a failing check" or "the prod deploy you triggered 4 minutes ago crashed." When the orchestrator's session ends, GitHub and Vercel become invisible — the harness has no callback channel for those systems.

The closest thing to deploy verification that exists is the **external-monitor pattern** shipped 2026-05-21 (`the prod-health-monitor instance shipped 2026-05-21`) — a generic SessionStart surfacer (`external-monitor-alert-surfacer.sh`) that reads JSON anomaly markers from a configured directory and presents them at the next session start. It works, it is proven (caught 6 real anomalies on first run), but it (1) requires a separate probe per target, (2) runs on a fixed cron — not coupled to deploys, (3) only surfaces on session start — not mid-turn, (4) has zero coupling to the specific PR / commit / deploy the orchestrator just shipped.

The user's specific failure pattern — orchestrator pushes, walks away, comes back hours later to discover CI failed or prod broke — is **structurally invisible to the harness as currently built**.

---

## 1. Inventory: what the harness has

### 1.1 Rules (Pattern-class — self-applied, no enforcement)

| File | Relevant rule | Enforcement |
|---|---|---|
| `adapters/claude-code/rules/deploy-to-production.md` | "Confirm the Vercel production deploy succeeded by checking `gh pr checks` or the Vercel dashboard" (step 4 of 5) | Pattern-only. No hook checks the agent ran this step. |
| `adapters/claude-code/rules/testing.md` ("Deployment Validation") | "A PR is not done until it deploys successfully. Sequence: commit → push → CI passes → deploy succeeds → feature verified → done." | Pattern-only. |
| `adapters/claude-code/rules/git-discipline.md` (Rule 2) | "After every merge to master, sync the user's main checkout." | Pattern-only. No hook detects "merged but did not sync." |
| `adapters/claude-code/rules/git.md` | "Confirm the Vercel production deploy" + auto-merge directive | Pattern-only. |

**Net:** four rules describe what the agent should DO. Zero of them have a hook backing them at the push/merge boundary. An agent that pushes and immediately moves on satisfies zero mechanical checks.

### 1.2 Hooks (Mechanism-class)

#### 1.2.1 Pre-push (local-only, no remote awareness)

- **`adapters/claude-code/hooks/pre-push-scan.sh`** — credential scanner. Scans diff for tokens / API keys. Does NOT check CI status or wait for anything. Wired via `core.hooksPath`.
- **`adapters/claude-code/hooks/pre-push-test-gate.sh`** — checks for a green-test receipt at `<repo>/.claude/state/test-receipt-<branch>-<sha>.txt` before allowing push to master / main. Opt-in per repo via `<repo>/.claude/pre-push-test-gate.enabled` marker. Bypass: `PT_PUSH_NO_TEST_GATE=1` or `--no-verify`. Receipt is written by the human-invoked `~/.claude/scripts/record-test-pass.sh` after running tests locally. **Does NOT watch CI on the remote.** This is a local "did you run tests" gate, not a deploy verification gate.

#### 1.2.2 Post-push / post-merge (does not exist)

- **There is NO hook that fires on `git push`, `gh pr merge`, `gh pr create`, or `vercel deploy` that watches CI on the remote.** `grep -rn "gh run watch\|--watch\|vercel inspect" adapters/claude-code/` returns zero matches.
- **There is NO hook that fires when a merge to master completes.** `automation-mode-gate.sh` is a PreToolUse gate that decides whether to ALLOW `git push` / `gh pr merge` / `vercel deploy` based on the per-project `automation-mode.json` config — it does not observe completion of those commands.

#### 1.2.3 External monitor (the only existing prod-verification mechanism)

- **`adapters/claude-code/hooks/external-monitor-alert-surfacer.sh`** (shipped 2026-05-21, PR #19): generic SessionStart hook. Reads JSON anomaly markers from `~/.claude/state/external-monitor-alerts/` (default; configurable). Surfaces up to 5 newest unacked entries as a system-reminder block at session start. Ack-by-sibling `.acked` marker. Self-test 6/6 PASS.
- Paired with an instance-specific HTTP probe at `tools/` (kept under `is_exempt()` per the instance-tooling boundary) and an operational runbook under `docs/operations/` that documents three scheduling options:
  - **Option A:** `scheduled-tasks` MCP cron — preferred, requires one user approval per task.
  - **Option B:** Windows Task Scheduler — fully autonomous, no Claude session needed.
  - **Option C:** Trigger.dev or cloud cron — rejected as overkill for this case.
- **What this catches:** anything the probe's route list explicitly checks at probe cadence (every 30 min).
- **What this does NOT catch:**
  - Failures between probe runs (up to 30 min latency).
  - Failures on routes not in the probe's `ROUTES` array.
  - Deploy failures that don't manifest as HTTP anomalies (e.g., build failed, deploy never promoted to prod, env var missing causing silent fallback).
  - PR-check failures (the probe checks production endpoints, not GitHub Actions status).
  - Anything in repos other than the one the probe targets.

#### 1.2.4 Session-end / next-session surfacing (passive)

- **`adapters/claude-code/hooks/pre-stop-verifier.sh`** — Stop hook. Sweeps plans for unverified tasks, malformed evidence, etc. Does NOT check CI / deploy state.
- **`adapters/claude-code/hooks/product-acceptance-gate.sh`** — Stop hook position 4. Blocks session end unless every ACTIVE plan has a runtime acceptance JSON artifact at `.claude/state/acceptance/<slug>/*.json` with matching `plan_commit_sha`. The acceptance artifact is written by `end-user-advocate` runtime mode and represents adversarial product observation. **This is the closest thing to a "verify the running product works" gate.** It is gated on plans that have `## Acceptance Scenarios` and are not `acceptance-exempt: true`. It runs against a live app (typically local dev server), not against production after a deploy.
- **`adapters/claude-code/hooks/continuation-enforcer.sh`** — Stop hook. Requires final response to end with exactly one of `DONE:` / `PAUSING:` / `BLOCKED:`. Does NOT check whether DONE is honest — e.g., "DONE: shipped X" without CI having passed is not caught.
- **Eight SessionStart hooks** (`discovery-surfacer.sh`, `spawned-task-result-surfacer.sh`, `external-monitor-alert-surfacer.sh`, `settings-divergence-detector.sh`, `plan-status-archival-sweep.sh`, `check-harness-sync.sh`, the goal-extraction pair, and the compact handler). None fetch GitHub PR check status, Vercel deploy status, or any remote-system state. They all read local files.

### 1.3 CI workflows

- **`.github/workflows/pr-template-check.yml`** — validates PR body has the capture-codify "What mechanism would have caught this?" section. Does NOT verify deploys.
- **No deploy-verification workflow** exists in the neural-lace repo itself (it's a harness repo with no deployment). Downstream projects have their own CI / Vercel integrations that the harness does not observe.

### 1.4 Scripts and skills

- **`adapters/claude-code/scripts/audit-merged-prs.sh`** — retroactive audit tool. Iterates `gh pr list --state merged --limit N`, runs the PR-template validator. Read-only; not invoked from any hook.
- **`adapters/claude-code/scripts/record-test-pass.sh`** — writes a test receipt for `pre-push-test-gate.sh`. Human-invoked.
- **`adapters/claude-code/scripts/start-plan.sh`** + **`close-plan.sh`** — plan-lifecycle automation. Do not touch CI / deploy state.
- **No skill** exists in `adapters/claude-code/skills/` for "watch this PR's CI", "verify prod deploy succeeded", "smoke-test the merged work", or "list PRs with failing checks." Misha would have to invoke `gh pr checks` / `gh run watch` / `vercel inspect` manually each time.

### 1.5 The orchestrator's between-turn context

Critical observation: when Dispatch sends a follow-up turn to the orchestrator, the only fresh inputs the orchestrator sees are (a) the user's new message, (b) the SessionStart hook output, (c) any tool results the orchestrator chooses to invoke. **None of (a) or (b) include CI / deploy status by default.** The orchestrator has to remember to run `gh pr checks` itself if it wants to know — and there is no hook that reminds it to.

---

## 2. Cataloguing the failures we keep hitting

The user's specific frustrations from this conversation map to a single failure class: **remote state changed (GitHub, Vercel, an external service) and the orchestrator never observed the change**. Five concrete instances:

### 2.1 PR #19 on neural-lace had a failing CI check unnoticed

A previous session's PR #19 (the external-monitor-alert-surfacer hook landing) sat with a failing PR-template-check CI for an extended period. The orchestrator that opened the PR did not check `gh pr checks` after creating it, did not poll while it ran, and reported `DONE` on the session even though the check was red on the remote. Misha had to surface it manually.

- **What would have caught it:** A post-`gh pr create` watcher that invokes `gh run watch` (or polls `gh pr checks`) until checks complete, then writes a marker file the next SessionStart surfacer can present. The session would have either (a) blocked on `DONE:` until checks went green, (b) downgraded to `PAUSING:` with the specific check failure, or (c) surfaced the failure on the next session start.

### 2.2 PR #304 Sentry — Vercel auto-promoted broken code to prod

A merge to master triggered the Vercel auto-deploy, the deploy went red (or went green but the code itself had a runtime regression). The orchestrator that merged the PR did not verify the deploy succeeded — and even if it had checked `vercel inspect` or hit a smoke-test URL, it didn't because the rule that says to do so is Pattern-only.

- **What would have caught it:** A post-`gh pr merge` smoke-probe that runs ~3 minutes after the merge (giving Vercel time to build + promote), hits a small set of critical routes (`/`, `/api/health`, key user-facing pages), and writes an alert marker if any return non-2xx / 3xx-to-login / 5xx / timeout. The external-monitor pattern is the canonical shape — just wired to fire on merge instead of cron.

### 2.3 PR #298 RBAC merge broke routes

Same shape as 2.2, but for a different PR's deploy. The harness has no mechanism that connects "this PR just merged" → "smoke-test this URL set in N minutes" → "alert if anomalies."

### 2.4 Conv Tree items 26/27/28 reported DONE on an un-re-merged branch

A session reported `DONE` on a feature branch's work without re-merging master into the branch, leaving the branch behind master. The work was technically built but not on the path to production. `continuation-enforcer.sh` accepted the `DONE:` marker because its format check is structural, not semantic — it does not verify "DONE actually shipped."

- **What would have caught it:** A `DONE:`-marker semantic check that compares the session's branch HEAD against `origin/master` and, if the branch is behind or has open PRs, downgrades to `PAUSING: branch is N commits behind master, needs merge before DONE`.

### 2.5 Rate-limited and died silently

A Dispatch session hit an Anthropic rate limit and was killed; the orchestrator's last partial response disappeared, the user never saw a `DONE:` or `BLOCKED:` marker. The harness has no mechanism that distinguishes "session ended normally" from "session died." Next session start has no signal that the prior session was killed.

- **What would have caught it:** A SessionStart hook that compares the most-recent transcript's last assistant message timestamp against the session-end signal in the local state; if no terminal-state marker was the last thing written, surface "prior session may have been killed — review transcript at `<path>` before continuing."

### 2.6 Open PR sat for hours with failing CI unnoticed

The PR opened in session A; session A ended (correctly or by rate-limit); the PR's CI ran and failed 6 minutes later; sessions B, C, D started and ended without surfacing the failure because nothing connects "open PRs in this repo" to "the orchestrator's between-turn context."

- **What would have caught it:** A SessionStart digest that runs `gh pr list --state open --search "is:open author:@me"` and surfaces any PR whose checks are red. (Or, with multi-repo support, runs the same query across every repo under `~/claude-projects/`.)

---

## 3. The structural pattern

Every failure in §2 is the same shape:

```
        [orchestrator turn ends]
                ↓
        [remote state changes — CI runs, deploy completes, PR check fires]
                ↓
        [next orchestrator turn starts]
                ↑
                └── orchestrator's context does NOT include the remote-state change
```

The harness has invested deeply in mechanisms that gate the orchestrator's **outputs** (pre-commit-tdd-gate, plan-edit-validator, runtime-verification-executor, wire-check-gate, scope-enforcement-gate, etc.). It has invested almost nothing in enriching the orchestrator's **inputs** with remote-state observations.

The external-monitor pattern is the lone exception, and it proves the pattern works — but it requires a probe-per-target and runs on its own cron schedule, decoupled from the agent's actions.

---

## 4. What does NOT exist (honest list)

The following machinery would have caught the failures above. None of it exists in the harness today:

1. **`gh run watch` wrapper around `git push`.** No mechanism waits for CI to complete after a push.
2. **Post-merge prod-smoke-probe.** No mechanism fires N minutes after `gh pr merge` to verify the deploy succeeded.
3. **PR-check digest on SessionStart.** No SessionStart hook lists open PRs across the user's repos and surfaces any with red checks.
4. **Vercel deployment-status webhook → file marker.** No integration with Vercel's webhook stream that writes alerts the surfacer would present.
5. **GitHub Actions failure → file marker.** Same as 4, for GitHub Actions check failures across all repos.
6. **`DONE:` semantic check** (vs the existing format check). No mechanism verifies the work the orchestrator claims is DONE actually reached master / production.
7. **Killed-session detector.** No SessionStart signal that the previous session ended without a terminal marker.
8. **Multi-repo PR-status sweep.** No mechanism iterates `~/claude-projects/*/` and reports PR state.

---

## 5. What DOES exist (the prior art the proposal builds on)

- The **external-monitor pattern** (`external-monitor-alert-surfacer.sh` + per-target probe + scheduled cron + runbook). Generic, proven, byte-tested. The right shape for "remote state → file marker → SessionStart surface" — just needs more probes wired to more triggers.
- The **`scheduled-tasks` MCP** integration (Option A in the runbook). Each scheduled task spawns a fresh ephemeral Claude Code session that can invoke any harness primitive (`gh`, `curl`, `vercel`, etc.). Higher quality and orchestrator-aware than Windows Task Scheduler.
- The **`automation-mode.json`** per-project config that classifies projects pre-customer vs customer-facing. This is the right place to declare "this project deploys to prod via Vercel; smoke-probe URLs are X, Y, Z."
- The **`audit-merged-prs.sh`** script — already iterates `gh pr list` and runs validators. Extends naturally to "list open PRs with red CI."
- The **`continuation-enforcer.sh`** Stop hook + `DONE:`/`PAUSING:`/`BLOCKED:` marker convention — the right place to add semantic checks ("DONE only if branch is on master / CI passed / deploy succeeded").
- The **`spawned-task-result-surfacer.sh`** SessionStart hook pattern — JSON marker per dispatched task, ack-by-sibling-marker, silent when empty. The canonical shape for "next session, here's what happened while you were gone."

The improvements proposal in `docs/proposals/harness-reliability-improvements-2026-05-21.md` lays out concrete mechanisms, ranking, and dependencies.

---

## 6. Cross-references

- **Proposal companion:** `docs/proposals/harness-reliability-improvements-2026-05-21.md`
- **External-monitor canonical example:** the runbook + archived plan for the prod-health-monitor instance shipped 2026-05-21 (instance-specific docs under `docs/operations/` and `docs/plans/archive/`; both `is_exempt()` from harness-hygiene because they're instance-tooling, not kit code)
- **External-monitor surfacer (the building block):** `adapters/claude-code/hooks/external-monitor-alert-surfacer.sh`
- **Existing deploy rules (Pattern-only):** `adapters/claude-code/rules/deploy-to-production.md`, `adapters/claude-code/rules/testing.md` ("Deployment Validation"), `adapters/claude-code/rules/git-discipline.md` Rule 2
- **Pre-push local gate (not remote-aware):** `adapters/claude-code/hooks/pre-push-test-gate.sh`
- **Automation-mode config:** `adapters/claude-code/hooks/automation-mode-gate.sh`
- **Continuation enforcer (where semantic DONE check would live):** `adapters/claude-code/hooks/continuation-enforcer.sh`
- **Session-end protocol rule:** `adapters/claude-code/rules/session-end-protocol.md`
