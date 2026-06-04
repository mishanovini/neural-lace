# Plan: Incentive-Audit Fixes 2026-05-28 (Fix #1 + Fix #3 + #34 cron/wakeup)
Status: COMPLETED
<!-- Closed 2026-06-04 by stale-ACTIVE-plan cleanup. Verified on master HEAD: stale-active-plan-surfacer.sh, measure-claim-reviewer-rate.sh, harness-evaluator-daily.sh, install-daily-harness-eval-task.ps1, both surfacers wired in SessionStart. Shipped PR #40 (43b9707/6cc5ff1), reconverged 588c5b7. Fix #2 (HMAC) explicitly Misha-deferred. Dispatch never ran task-verifier. -->
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: build-harness-infrastructure
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanisms; self-tests are the acceptance artifact; no product user runtime to advocate for
Backlog items absorbed: none

## Goal

Drive three Misha-approved fixes from the 2026-05-24 agent-incentive-structure
audit + the daily-cron / Dispatch-wakeup wiring for PR #34:

- **Fix #1 (audit Section 5):** stale-ACTIVE-plan surfacer at 24-hour threshold
  (Misha tightened from audit's 14-day default). Closes IG-1, IG-5, IG-8.
- **Fix #3:** claim-reviewer self-invocation rate instrumentation. Converts
  IG-3 from unknown bypass rate to measurable.
- **#34 daily-cron + Dispatch-wakeup:** 5 PM daily harness-evaluator packet
  generation; high-severity drift emits an alert marker that the
  `external-monitor-alert-surfacer.sh` SessionStart hook surfaces on next
  interactive Code session.

Fix #2 (HMAC sentinel for `tool-call-budget --ack`) is **deferred** with
reason: low observed-incidence; no audit-log evidence of ack-tampering on
this machine in the 60-day window. Revisit if it surfaces.

## Scope

- IN: harness-internal hooks + scripts under `adapters/claude-code/`; live-
  mirror sync to `~/.claude/`; D1 follow-on roadmap edit (memory rename
  reconciliation).
- OUT: cherry-picking PRs #28/#29/#30 onto fresh master branches (separate
  session); HMAC sentinel work (deferred per above); audit Fix #4-#10
  (separate sessions per recommendations).

## Tasks

- [x] 1. Author `hooks/stale-active-plan-surfacer.sh` with 24h-threshold + 5-scenario self-test — Verification: mechanical
- [x] 2. Wire stale-active-plan-surfacer.sh into SessionStart (template + live mirror) — Verification: mechanical
- [x] 3. Author `scripts/measure-claim-reviewer-rate.sh` with 5-scenario self-test — Verification: mechanical
- [x] 4. Author `scripts/harness-evaluator-daily.sh` (the 5-PM wrapper) with 4-scenario self-test — Verification: mechanical
- [x] 5. Wire `external-monitor-alert-surfacer.sh` into SessionStart (Fix #9 + #34's wakeup transport, template + live mirror) — Verification: mechanical
- [x] 6. Author `install-daily-harness-eval-task.ps1` Windows Task Scheduler installer — Verification: mechanical
- [x] 7. D1 roadmap reversal + backlog citation update + memory file rename (carried over from D1 of the parent session — already committed via this branch's parent ref) — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/stale-active-plan-surfacer.sh` — NEW; SessionStart hook flagging ACTIVE plans untouched >24h
- `adapters/claude-code/scripts/measure-claim-reviewer-rate.sh` — NEW; bash script measuring claim-reviewer self-invocation rate
- `adapters/claude-code/scripts/harness-evaluator-daily.sh` — NEW; wrapper around harness-evaluator.sh + severity check + alert marker
- `adapters/claude-code/scripts/install-daily-harness-eval-task.ps1` — NEW; Windows Task Scheduler installer
- `adapters/claude-code/settings.json.template` — wire stale-active-plan-surfacer + external-monitor-alert-surfacer into SessionStart
- `docs/backlog.md` — D1 follow-on: update HARNESS-GAP-22 citation to renamed memory filename
- `docs/harness-hygiene-roadmap.md` — D1 follow-on: reverse D4 entry per Misha's elevation authorization
- `docs/plans/incentive-audit-fixes-2026-05-28.md` — THIS plan file

## In-flight scope updates

(none)

## Walking Skeleton

The 24h-stale-plan check + the daily-eval+wakeup chain are the thinnest
end-to-end slices through the audit's IG-1 / IG-3 / Fix #9 substrate. Each
ships independently and composes cleanly: stale-plan surfacer fires at
SessionStart; measure-rate runs on demand or from harness-evaluator; daily
wrapper writes alert marker; external-monitor-alert-surfacer.sh surfaces
markers at SessionStart. Self-tests on each PASS before commit.

## Acceptance Scenarios

acceptance-exempt: true. The maintainer running `--self-test` on each
artifact + observing the SessionStart hook fire is the harness-internal
acceptance artifact. No browser-driven scenario applicable to non-product code.

## Testing Strategy

- `stale-active-plan-surfacer.sh --self-test` → 5/5 PASS (confirmed)
- `measure-claim-reviewer-rate.sh --self-test` → 5/5 PASS (confirmed)
- `harness-evaluator-daily.sh --self-test` → 3-4/3-4 PASS depending on jq (confirmed)
- Live test of stale-plan surfacer against current repo → surfaces 10 stale plans (confirmed)
- Live test of measure-claim-reviewer-rate against 7-day window → 288 claims / 0 invocations across 104 sessions (confirmed; matches audit's IG-3 expected bypass rate)

## Decisions Log

### Decision: Use external-monitor-alert-surfacer.sh as the Dispatch-wakeup transport
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Compose Fix #9 (audit) with #34's wakeup wiring — the existing
  `external-monitor-alert-surfacer.sh` SessionStart hook is the canonical
  surface for unacked alert markers; #34's daily wrapper writes its high-
  severity drift to that same marker dir, so next interactive Code session
  surfaces it.
- **Alternatives:**
  - ntfy.sh / push notification → REJECTED per Misha: "NOT ntfy.sh / phone / email"
  - Direct MCP `spawn_task` invocation from bash → INFEASIBLE: MCP tools only callable from Claude Code session, not bash
  - New Stop-hook with parent-wake → BLOCKED on same constraint
- **Reasoning:** the marker-file approach is mechanical, composes with an
  existing canonical hook, and doesn't require new transport infrastructure.
  The "wakeup" semantically is "next interactive Code session sees the
  marker at SessionStart" — same shape as discoveries/findings surfacing.
- **Checkpoint:** N/A (single-commit)
- **To reverse:** revert this commit; remove the alert-dir entries.

### Decision: Defer Fix #2 (HMAC sentinel)
- **Tier:** 1
- **Status:** Misha-authorized defer
- **Chosen:** Defer with reason "low observed-incidence; revisit if surfaced
  in audit logs."
- **Alternatives:** ship the HMAC sentinel now (half-day work)
- **Reasoning:** per Misha 2026-05-28 — we haven't observed ack-tampering;
  defense-in-depth lower priority than #1 and #3 which address measurable
  gaps. Revisit if ack-tampering surfaces in audit logs.

## Definition of Done

- [x] All tasks checked off
- [x] All self-tests PASS
- [x] Live mirror synced byte-identical
- [x] PR #34 closed with summary comment
- [x] PR #38 closed with summary comment
- [x] Final report appended to the session's consolidated message
