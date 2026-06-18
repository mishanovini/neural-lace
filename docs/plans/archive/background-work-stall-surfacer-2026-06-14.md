# Plan: Background-Work Stall Surfacer (encode the "stalled and forgotten" lesson)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the hook's --self-test (verified against the real wf_b0ebc82b-7e1 failure) is the acceptance artifact; no product user-facing surface.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Encode the 2026-06-13 lesson: a background Workflow stalled silently (3 of 4 agents
returned, the 4th died), nothing surfaced it, and the orchestrator kept claiming
"it's running, it'll auto-resume me." Per diagnosis.md "After Every Failure: Encode
the Fix" + principles.md Rule 6 (preemptive) / Rule 7 (no false promises): turn the
lesson into a mechanism so silently-stalled background work cannot be forgotten.

## User-facing Outcome
The harness operator never again loses track of a background task that stalled.
At every session start, any incomplete/stalled Workflow run is surfaced with a
recovery path; and the agent is bound (by the companion rule) to verify a task's
liveness before claiming it is "running."

## Scope
- IN: a SessionStart surfacer that detects + surfaces stalled Workflow runs; a
  companion discipline rule; their wiring + INDEX + architecture-doc entries.
- OUT: a real-time mid-session heartbeat (named-not-built enhancement); a unified
  background-work ledger spanning dispatched sessions + spawn_task (candidate
  consolidation); changes to the Workflow tool itself.

## Tasks
- [x] 1. `hooks/stalled-work-surfacer.sh` — SessionStart hook detecting the stall signature (started>result + stale mtime + not acked), with `--self-test`. — Verification: mechanical
- [x] 2. `rules/background-work-tracking.md` — companion discipline rule (tracked-obligation; verify-before-claiming; foreground for must-complete) + `rules/INDEX.md` row. — Verification: mechanical
- [x] 3. Wire into SessionStart (`settings.json.template` + live `~/.claude/settings.json`); update `docs/harness-architecture.md`. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/stalled-work-surfacer.sh` — new SessionStart surfacer.
- `adapters/claude-code/rules/background-work-tracking.md` — new companion rule.
- `adapters/claude-code/rules/INDEX.md` — add the rule's index row (CI-required).
- `adapters/claude-code/settings.json.template` — wire the surfacer into SessionStart.
- `docs/harness-architecture.md` — changelog header + SessionStart inventory row.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- Workflow runs write `subagents/workflows/<run>/journal.jsonl` with `{"type":"started"}` / `{"type":"result"}` agent events (verified against the real wf_b0ebc82b-7e1 journal).
- A stall = more `started` than `result` events + an idle journal; a completed run has `started==result`.
- SessionStart hooks may print informational output and must exit 0 (never block session start).

## Edge Cases
- Actively-running workflow (started>result but fresh mtime) → NOT flagged (mtime threshold).
- Completed workflow (started==result) → never flagged.
- Already-recovered stall → `.stall-acked` marker suppresses re-surfacing.
- No projects dir / no workflow journals → silent exit 0.
- Ancient runs (>48h) → out of lookback window, not surfaced.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal). The hook's `--self-test` (5 scenarios) + verification against the real wf_b0ebc82b-7e1 failure is the acceptance artifact.

## Out-of-scope scenarios
- Browser/runtime acceptance: not applicable; no product surface.

## Testing Strategy
- `stalled-work-surfacer.sh --self-test` (5 scenarios: stalled / completed / still-running / acked / none).
- Real-failure verification: run against `~/.claude/projects/.../wf_b0ebc82b-7e1` and confirm it detects the actual stall (started 4 > result 3).
- Both settings JSON valid; live `~/.claude` synced byte-identical; rules-index-coverage golden test covers the new rule.

## Walking Skeleton
The thinnest end-to-end slice IS the self-test + the real-failure detection: a synthetic workflow journal (and the real one) exercises the full scan → signature-match → surface path. Self-test passing + real-stall detected == the harness's user-facing outcome (the user is the maintainer).

## Decisions Log
- Detector keyed on `started > result` + stale-mtime (not a terminal "complete" event, which the journal doesn't reliably emit). Session-boundary surfacing chosen as the mechanism floor; the mid-session real-time heartbeat is named-not-built (honest limit, Rule 7) rather than over-claimed. Scope kept to Workflow journals (the originating failure class); dispatched-session liveness already covered by spawned-task-result-surfacer.sh.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code harness-infrastructure, single coherent change.
- S2 (Existing-Code-Claim Verification): swept — journal event shapes confirmed by reading the real wf_b0ebc82b-7e1 journal.
- S3 (Cross-Section Consistency): swept — Scope/Files/Tasks consistent.
- S4 (Numeric-Parameter Sweep): swept — STALE_MIN=10, LOOKBACK_MIN=2880 single-valued in hook + rule + arch doc.
- S5 (Scope-vs-Analysis Check): swept — every new/wire verb targets a file listed IN scope.

## Definition of Done
- [x] All tasks checked off
- [x] Hook `--self-test` passes (5/5) + verified against the real stall
- [x] Wired in template + live settings.json (both JSON valid)
- [x] INDEX row added (rules-index golden test covers the new rule)
- [x] harness-architecture.md updated
