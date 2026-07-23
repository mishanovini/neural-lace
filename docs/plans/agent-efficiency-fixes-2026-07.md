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
- 2026-07-23: `adapters/claude-code/hooks/find-disk-scan-gate.sh` — T4 block-mode gate
- 2026-07-23: `adapters/claude-code/settings.json.template` — T4 PreToolUse wiring + T5 shim-wiring removals
- 2026-07-23: `adapters/claude-code/scripts/blocking-budget-check.js` — T4 budget cap 13->14 (named rationale); T5 may re-lower
- 2026-07-23: `adapters/claude-code/manifest.json` — T4 entry + T5 retired-entry updates
- 2026-07-23: `adapters/claude-code/hooks/lib/sessionstart-singleflight.sh` — T3 extends the existing lib
- 2026-07-23: `adapters/claude-code/hooks/*.sh` — T7 path-in-block-message sweep (message text only) + T2/T3 guard/lock edits
- 2026-07-23: `adapters/claude-code/attic/**` — T5 shim retirements
- 2026-07-23: `adapters/claude-code/install.sh` — T5 prune_retired_files additions
- 2026-07-23: `docs/harness-architecture.md` — regen (structural changes)

## In-flight amendments (2026-07-23, orchestrating session 29f2930a — operator authorized "build the efficiency batch")
- T4 is built as a BLOCK (not warn) with a structured-waiver hatch and fail-open on internal error —
  operator-facing rationale delivered in chat 2026-07-23: a drive-wide `find /` has no legitimate use
  on this machine (golden scenario: the 2026-07-20 live `find / -iname scope-enforcement-gate*` at 13%
  CPU, killed by hand). Plan text said "warn"; decide-and-go per §8, reversible (flip block→warn).
- NEW SWEEP TASK T7 — path-in-block-message convention: every gate block message names its OWN
  absolute hook path, removing the reason agents hunt the filesystem for gate sources (the observed
  trigger for the `find /` class). Scope: hooks/*.sh block-message emitters EXCLUDING files T2/T3 own
  (session-start-digest.sh, session-start-auto-install.sh, harness-doctor.sh).
- T6 evidence (operator, 2026-07-23, screenshots in session 29f2930a): Defender exclusions verified
  live — folders incl. ~/.claude, claude-projects, Temp/claude, Temp/claude-scratch, C:/Program
  Files/Git; process exclusions bash/git/claude/node et al. Exceeds the task's asked set.
- Scope additions: `adapters/claude-code/hooks/find-disk-scan-gate.sh` (T4 block-mode name),
  `adapters/claude-code/settings.json.template` (T4 wiring + T5 shim removals),
  `adapters/claude-code/manifest.json` (T4 entry + T5 entry updates), `docs/harness-architecture.md`
  (regen), `adapters/claude-code/hooks/lib/sessionstart-singleflight.sh` (T3 extends the EXISTING lib).

## Evidence Log

### T2 trace RESOLVED (2026-07-23, orchestrator, live capture mid-storm — PROVEN)
- The repeated `session-start-digest.sh --self-test` invoker is **harness-doctor.sh's
  `wave-e-e1-digest` check (~line 704)**: it executes the digest's FULL self-test suite inline on
  every doctor run — and `--quick` fires on every SessionStart, every session RESUME (each turn of
  an active conversation, each subagent dispatch cycle), plus the hourly NL-health-tick
  (`scripts/health-tick.sh`).
- Observed live at ~10:15-10:26 local: 7 concurrent live-path digest `--self-test` processes
  (spawn cadence minutes apart, each 12+ min under load — piling faster than finishing), 3
  concurrent live-path `harness-doctor.sh --quick`, 94 bash.exe total; operator's Claude desktop
  app unresponsive. Orchestrator killed the 7 redundant self-tests + 2 duplicate doctor runs as
  live mitigation; class re-piles with session activity until T2/T3 land.
- Defender note: exclusions verified in place (T6) yet Antimalware still 25% CPU during the storm —
  behavior monitoring scans process creation regardless of exclusions; confirms fork-RATE reduction
  (T2/T3) is the load-bearing fix.
- 2026-07-23 (T3 builder trail, union-kept at integration): the shared lock lib
  session-start-auto-install.sh already uses is the SAME lib T3 extends to harness-doctor.sh and
  session-start-digest.sh; separately declared above by the orchestrator — this line preserves the
  builder's own scope-drift trail.

## Notes
T2/T3 are the highest-leverage (they contain the fork storm). T1 is bookkeeping to get the diagnosis
onto master for the operator's review session (their explicit request: "land on master").
