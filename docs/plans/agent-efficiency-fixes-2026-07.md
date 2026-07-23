# Plan — Agent Efficiency Fixes (Windows spawn tax + self-test-sweep fork storm)

Status: ACTIVE
Mode: code
Owner: interactive session (2026-07-20)
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal; demonstrated via each artifact's `--self-test` + live process-count re-measure)

## Why
The 2026-07-13 profile diagnosed the Windows process-spawn tax + hook latency but shipped only docs.
A week later the heaviness returned (see docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md):
same unfixed classes + a new self-test-sweep fork-storm amplifier + more concurrent sessions. This plan
converts the diagnosis into shipped fixes. Diagnosis of record:
- docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md
- docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md

## Files to Modify/Create
- docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md (created; the profile)
- docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md (created; the recurrence diagnosis)
- docs/plans/agent-efficiency-fixes-2026-07.md (this plan)
- adapters/claude-code/hooks/session-start-digest.sh (add self-test-sweep origin gate) — task T2
- adapters/claude-code/hooks/session-start-auto-install.sh / harness-doctor.sh (single-flight lock) — task T3
- (new) adapters/claude-code/hooks/find-disk-scan-warn.sh (PreToolUse warn on `find /`) — task T4

## Tasks
- [ ] T1 — Land the two diagnosis lessons + this plan on master (this commit). Verification: mechanical (files on master).
- [ ] T2 — Trace what invokes `session-start-digest.sh --self-test` on the live machine and gate it so
      self-test sweeps do not run on normal session start / ticks; add an origin guard. Verification: full
      (re-measure concurrent `--self-test` process count → 0 on a normal session start).
- [ ] T3 — Ship SESSIONSTART-SINGLEFLIGHT-01: single-flight lock so doctor/digest/auto-install don't
      run concurrently across simultaneously-starting sessions. Verification: full (bash.exe count under
      concurrent starts stays bounded).
- [ ] T4 — `find /` PreToolUse warn-hook suggesting Glob/`git rev-parse`. Verification: full (--self-test).
- [ ] T5 — Retire dead `exit 0` hook shims (tool-call-budget.sh et al.) from live wiring. Verification: contract.
- [ ] T6 — Operator: Windows Defender exclusions for ~/.claude, Git Bash, repo roots (admin). Verification: manual.

## In-flight scope updates
- 2026-07-22: docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md — the recurrence diagnosis this plan converts to build work
- 2026-07-22: docs/plans/agent-efficiency-fixes-2026-07.md — this plan file

## Notes
T2/T3 are the highest-leverage (they contain the fork storm). T1 is bookkeeping to get the diagnosis
onto master for the operator's review session (their explicit request: "land on master").
