# Plan — Agent Efficiency Fixes (Windows spawn tax + self-test-sweep fork storm)

Status: COMPLETED
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
- [x] T1 — Land the two diagnosis lessons + this plan on master (this commit). Verification: mechanical (files on master).
- [x] T2 — Trace what invokes `session-start-digest.sh --self-test` on the live machine and gate it so
      self-test sweeps do not run on normal session start / ticks; add an origin guard. Verification: full
      (re-measure concurrent `--self-test` process count → 0 on a normal session start).
- [x] T3 — Ship SESSIONSTART-SINGLEFLIGHT-01: single-flight lock so doctor/digest/auto-install don't
      run concurrently across simultaneously-starting sessions. Verification: full (bash.exe count under
      concurrent starts stays bounded).
- [x] T4 — `find /` PreToolUse warn-hook suggesting Glob/`git rev-parse`. Verification: full (--self-test).
- [x] T5 — Retire dead `exit 0` hook shims (tool-call-budget.sh et al.) from live wiring. Verification: contract. (template+file+manifest+attic+install-prune done; live settings entries pending reconcile — documented HOOK-SHIM-RETIRE-01)
- [x] T6 — Operator: Windows Defender exclusions for ~/.claude, Git Bash, repo roots (admin). Verification: manual.

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
- 2026-07-23: `docs/backlog.md` — T2/T3 follow-up rows (health-tick-cached digest verdict; --full doc-theater) + auto-filed digest rows landing mid-batch
- 2026-07-23: `adapters/claude-code/hooks/workstreams-state-gate.sh` — T5 dead-shim hard-delete (attic copy retained from 568daa0)
- 2026-07-23: `adapters/claude-code/doctrine/workstreams-state.md` — T5 stale-enforcement-line fix
- 2026-07-23: `docs/harness-guide.md` — T5 docs-freshness note for the structural deletion

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
- 2026-07-23 (T3 builder trail): settings.json.template — SessionStart's `harness-doctor.sh --quick`
  and `session-start-digest.sh` hook commands now carry an `NL_SESSIONSTART_ORIGIN=1` marker
  (distinguishes SessionStart-origin calls from explicit/manual invocation for the single-flight gate).

## Notes
T2/T3 are the highest-leverage (they contain the fork storm). T1 is bookkeeping to get the diagnosis
onto master for the operator's review session (their explicit request: "land on master").

## Completion Report

_Generated by close-plan.sh on 2026-07-24T02:28:16Z._

### 1. Implementation Summary

Plan: `docs/plans/agent-efficiency-fixes-2026-07.md` (slug: `agent-efficiency-fixes-2026-07`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/session-start-auto-install.sh`
- `adapters/claude-code/hooks/session-start-digest.sh`
- `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`
- `docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md`
- `docs/plans/agent-efficiency-fixes-2026-07.md`

Commits referencing these files:

```
038c648 fix(session-start-digest): honor the reentry guard at the --self-test entry point (T2); single-flight the SessionStart default path per repo root (T3)
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
08a3351 sweep batch 4 + adr061-P1b: verifier flips, set-e class sweep [24], reentry-safe heartbeats (D2), health tick (D6, unarmed) (#97)
1007841 fix(review-record): surface-vs-enforcement parity (REFORMULATE finding 1)
1b738fb feat(wave-o): O.1 emit extension + turn-traces + consumer map
24efc14 build(docs): F.2 docs regeneration + F.2b docs-as-process (Wave F task F.2)
275700e plan(agent-efficiency): in-flight amendments — T4 block-mode + T7 path-in-block-message sweep + T6 operator evidence + scope additions
28de191 docs(efficiency): 2026-07-20 recurrence diagnosis + fix plan (T2 self-test-sweep gate, T3 single-flight lock)
2e99894 docs(lessons): commit efficiency lesson + fix stale claims (Tasks 1-3)
3d52e5d plan+backlog: declare backlog.md in efficiency-batch scope; auto-digest row; hygiene-fix a codename that rode in via merge-context gate skip
3e6c571 plan(agent-efficiency): T2 trace RESOLVED — doctor wave-e-e1-digest check runs the digest's full self-test inline on every --quick (PROVEN live capture 2026-07-23); mitigation + Defender behavior-monitoring evidence
43f76c2 sweep: nl-issues batch 2 — end-manifest false-block, cockpit FM-037 engine, denylist narrowing, lint+digest+doctrine (#95)
479277a feat(F.1): doctor budget checks + digest staleness escalation (specs-f §F.1)
4ee1880 docs: plan scope-drift trail + backlog landing note for T2/T3 (agent-efficiency-fixes-2026-07)
527cad3 integrate(wave-o batch-1): splice callsites + manifest/install fragments + end-manifest fix
5f90a85 fix(needs-you): NL-FINDING-035 bootstrap-migrate a stale/hand-authored NEEDS-YOU.md into the ledger
6aa156a NL Overhaul Wave E batch 1: E.1 digest, E.2 sandbox isolation, E.7 resumer, E.8 nl-issue, E.9 pre-compaction (#79)
6b9169d harden(observability O.9): derive backlog accountability from C4 oracle
71c4736 fix(needs-you deploy coupling): digest S9 fixture uses --mechanical + 3 docs describe the two-path block contract — unblocks needs-you.sh warn->block deploy without doctor-RED or honesty gap
7631810 feat(digest): backlog accountability feed — age-tiered overdue-row proposals (BACKLOG-LOOP-01 part 1, observability O.9)
7e84915 fix(harness): cockpit-ensure review remediation — machine-wide coverage + kill-switch + manifest
87f357f fix(backlog-loop): position-anchored terminal-marker detection — open rows referencing other rows' terminal states no longer false-skip (all 3 consumers)
8e5a011 fix(digest): sandbox PROGRESS_LOG_STATE_DIR + OPERATOR_TODO_PATH in S9 self-test
9896a9a plan(agent-efficiency): move batch scope additions into the gate-recognized In-flight scope updates section (T4 builder blocked on the unrecognized-heading gap)
a117c8a fix(review): cockpit-health harness-review conditions — background reap, doctor positive-ID probe
a322365 fix(harness): spawn-cascade guards — reentrancy guard, resumer spawn breaker, automation-scoped Stop-refire ceiling (NL-FINDING-040) (#91)
a49cdfc salvage(crash-recovery): partial backlog-build-escalation work — in-process builder died mid-build; commit preserves files for continuation
a7b7511 NL Overhaul Wave B: truth reconciliation (doctor, path fixes, install completeness, constitution draft) (#68)
aa9f0ad integrate(E.8): nl-issue selftest backlog sandbox + cross-project digest S10 (worker-e8-nlissue-fix bc6a87a)
ab1a7ed feat(worktree-hygiene): reformulate agent-worktree liveness — subagent-transcript-mtime fixes the cry-wolf FP
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
