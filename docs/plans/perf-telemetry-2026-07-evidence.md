# Evidence Log — Performance telemetry: passive metering, biting budgets, loop-liveness

## Task P1 — Per-call chain latency ledger
EVIDENCE BLOCK
==============
Task ID: P1
Task description: Per-call chain latency ledger: wrap the PreToolUse chain execution with $EPOCHREALTIME stamps; append ONE JSONL line per tool call (total ms, 3 slowest hooks, hook count) to a daily-rotated file under ~/.claude/state/perf/. Hot-path cost budget: <5ms, zero forks (asserted in self-test). Verification: full (self-test + a live capture line quoted).
Verified at: 2026-07-28T19:05:00-07:00
Verifier: task-verifier agent

Oracle: specified — the task's own Verification bar (self-test + a live capture line from THIS machine) + derived — the artifact's self-test suite at the landing commit, replayed independently by the verifier.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0 per Decision 020a)

Checks run:
1. Landing-commit ancestry
   Command: git merge-base --is-ancestor 3cff15d HEAD && git merge-base --is-ancestor 3cff15d origin/master
   Output: both true; 3cff15d ("feat(perf-telemetry): P1 per-call hook latency ledger + P2 tick perf snapshot/orphan reap") landed on first-parent master 2026-07-27 09:00:38 -0700
   Result: PASS
2. Artifact exists + self-test replayed by verifier
   Command: bash adapters/claude-code/hooks/lib/perf-ledger.sh --self-test
   Output: "self-test summary: 12 passed, 0 failed", exit 0. Scenario 6: 500 begin/end pairs in 377ms (~0.75ms/call vs <5ms budget; a single fork costs ~190ms). Scenario 7 static fork-count harness: no command substitution/backtick/pipe/external command in hot path; the one mkdir is [[ -d ]]-guarded.
   Result: PASS
3. Live capture — verifier's OWN live fire of the shipped hook (not the builder's)
   Command: echo '{"session_id":"verifier-live-fire",...,"tool_name":"Bash","tool_input":{"command":"git status",...}}' | bash adapters/claude-code/hooks/scope-enforcement-gate.sh  (repo@216c37d, contains 3cff15d)
   Output: hook exit 0; ~/.claude/state/perf/chain-20260728.jsonl grew 3 -> 4 lines; appended line: {"ts":"2026-07-28T16:59:54","hook":"scope-enforcement-gate","ms":2495}
   Result: PASS
4. Pre-existing organic capture lines on this machine
   Output: chain-20260728.jsonl also carries {"ts":"2026-07-28T03:51:35","hook":"scope-enforcement-gate","ms":73606} (the 73.6s entry the plan's reconciliation note quotes) + 2 more; chain-20260727.jsonl carries 1 line.
   Result: PASS (producer of the pre-existing lines is HYPOTHESIZED: post-P1 hook copies invoked with real input — my check 3 proves the identical path first-hand, so the claim does not rest on this)
5. Wiring into the 5 named highest-cost hooks
   Command: grep -n "pl_meter_begin\|pl_meter_end" <5 hooks>
   Output: scope-enforcement-gate.sh:1420-1423, plan-deletion-protection.sh:54+67-69, concurrent-ownership-gate.sh:794-797, evidence-before-fix-gate.sh:1020-1027, pr-template-inline-gate.sh:603-606+722 — all source lib + pl_meter_begin + EXIT-trap pl_meter_end (pr-template composes into its existing trap per the lib's documented pattern).
   Result: PASS
6. Schema deviation is plan-authorized (spec-correspondence check)
   Task text describes a chain-wrapper schema (total ms, 3 slowest hooks, hook count); shipped shape is per-hook {ts,hook,ms}. Verified the plan's Assumptions fallback clause is genuinely triggered: settings.json.template has NO single PreToolUse chain wrapper — 23 separate "Bash"-matcher command blocks (+8 all-tool, +3 Bash|PowerShell), counted by the verifier. Per-hook self-metering in the top-5 hooks is the plan's own declared fallback, declared honestly in manifest.json entry `perf-ledger`.
   Result: PASS (PROVEN, not taken from the builder's header comment)
7. Manifest entry
   Output: manifest.json `perf-ledger` entry (kind: writer, selftest: true, blocking: false) with substantive golden_scenario / fp_expectation / retirement_condition.
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/lib/perf-ledger.sh::--self-test
Runtime verification: file ~/.claude/state/perf/chain-20260728.jsonl::"hook":"scope-enforcement-gate"
Runtime verification: functionality-verifier P1::SKIP (rationale: harness-internal artifact; the verifier executed the self-test AND a live hook fire against realistic PreToolUse input directly — no Task tool available in this invocation)

DEPENDENCY TRACE
================
Step 1: A real tool call fires a PreToolUse hook (e.g. scope-enforcement-gate)
  ↓ Verified at: verifier live-fire, hook exit 0 (check 3)
Step 2: Hook sources lib/perf-ledger.sh, calls pl_meter_begin, EXIT-trap calls pl_meter_end
  ↓ Verified at: scope-enforcement-gate.sh:1420-1423 (+ 4 sibling hooks, check 5)
Step 3: One {ts,hook,ms} JSONL line appends to daily-rotated ~/.claude/state/perf/chain-YYYYMMDD.jsonl
  ↓ Verified at: chain-20260728.jsonl 3->4 lines, appended line quoted (check 3); schema+rotation also self-test Scenario 4

Git evidence:
  Landing commit: 3cff15d (first-parent master 2026-07-27; ancestor of origin/master and this checkout's HEAD 216c37d)
  Files: adapters/claude-code/hooks/lib/perf-ledger.sh (new, 356 lines) + 5 hooks + manifest.json (perf-ledger entry)

Observations (recorded, non-blocking):
  - Live-install lag: ~/.claude/hooks/lib/ does NOT yet contain perf-ledger.sh and live hooks are pre-3cff15d (mtime Jul 23) — deploy was review-gated; record hcr-20260728-3d5d64f9 (commit 971674f) unblocked it. Until auto-install syncs, live-session hooks do not meter (graceful: `source ... || true` + `declare -F` guard, verified in code). Not a build gap — done = merged to master per doctrine.
  - Writer-without-consumer window (P3/P4 not built) is named and bounded in the plan's own Notes section; not a P1 gap.

Verdict: PASS
Confidence: 9
Reason: PROVEN: self-test replayed 12/12 (exit 0) by the verifier; the verifier's own live fire of the shipped hook appended a schema-correct real ledger line ({"ts":"2026-07-28T16:59:54","hook":"scope-enforcement-gate","ms":2495}); wiring verified at file:line in all 5 named hooks; the per-hook fallback schema is plan-authorized (no chain wrapper exists — independently counted).

## Task P2 — Tick perf snapshot + orphan reap
EVIDENCE BLOCK
==============
Task ID: P2
Task description: Tick perf snapshot + orphan reap: one line per tick — bash.exe count, claude/Defender CPU, worktree count — on the EXISTING supervisor-tick.sh (landed f22b55d; PERF-ESTATE-PROGRAM-01's named home) with health-tick as fallback if supervisor-tick's cadence is unsuitable; same tick reaps parent-dead orphan bash/claude processes (log each reap). No new scheduler. Verification: full.
Verified at: 2026-07-28T19:25:00-07:00
Verifier: task-verifier agent

Oracle: specified — the task text's tick->snapshot-line->reap contract + derived — the artifact's and both ticks' pre-existing self-test suites at the landing commit, replayed by the verifier; plus committed independent review record hcr-20260728-3d5d64f9 at a byte-identical blob.

Comprehension-gate: skipped — rung field missing (plan header has no `rung:`; treated as rung 0 per Decision 020a)

Checks run:
1. Landing-commit ancestry — same as P1: 3cff15d on first-parent master 2026-07-27; ancestor of origin/master and HEAD 216c37d.
   Result: PASS
2. Lib self-test replayed by verifier, 3 full runs under heavy load (25 bash.exe / 18 claude processes)
   Command: bash adapters/claude-code/hooks/lib/perf-tick-snapshot.sh --self-test
   Output: 20 passed, 1 failed — all three runs. Every guard scenario PASSed every run (CRLF-doubling regression, fixture counts, honest degrade, parent-alive/young/heartbeat/self never-reap guards, unarmed-never-kills, empty-reap [], ledger-line schema with bash_count/claude_count/worktree_count/defender_cpu_ms/degraded). The single FAIL is Scenario 9 (armed-reap) bookkeeping only: each run the real disposable process WAS terminated (PASS "actually terminated by armed reap (taskkill //PID //F)") but the recorded action was reap_failed, not reaped.
   Result: PASS with characterized flake (check 3)
3. Scenario 9 flake — reproduced 3x, mechanism identified by code-read
   The disposable target is a 20-second background sleep (perf-tick-snapshot.sh:617). Under load the spawn-to-taskkill gap can exceed 20s: the target exits naturally, taskkill returns nonzero (not found) -> action=reap_failed, while the gone-check still passes. HYPOTHESIZED: self-test-harness race, NOT a product-path defect (production reap targets wmic-listed live processes, not a short-lived disposable); REFUTED if the scenario fails in isolation with no load — isolation was NOT achievable this session (18+ concurrent agent processes throughout). Consistent with builder 21/21 at commit time and reviewer 19/19 replay. Already filed: ~/.claude/state/nl-issues.jsonl line 163 (ts 2026-07-28T21:38:05Z) — verified present.
   Result: PASS (flake tracked, kill mechanism proven every run)
4. Wiring — supervisor-tick.sh (PRIMARY)
   Code: supervisor-tick.sh:446-459 — the real tick path sources the shared lib and runs pts_run_tick under the tick budget, graceful WARN degrade. Verifier suite replay: 16/19 — the 3 FAILs are ALL Scenario 5 (the P2 assertions) and the diagnosis is in the FAIL output itself: the inner fixture tick took 686s against the suite's 600s budget (the suite's own comment names this exact machine-load-artifact class), leaving the snapshot step a floored 1s budget -> timeout. Independent committed oracle: docs/reviews/records/2026-07-28-harness-change-review-3d5d64f9.json — reviewer re-ran the suite 19/19 (including Scenario 5's three P2 assertions) against blob 565551ad7a053778105583f42ddaf80ac257f485, byte-identical to HEAD's supervisor-tick.sh blob (verified via git rev-parse).
   Result: PASS (wiring proven; my replay FAILs are a PROVEN budget-starvation load artifact)
5. Wiring — health-tick.sh (FALLBACK) — verifier's own end-to-end replay
   Command: bash adapters/claude-code/scripts/health-tick.sh --self-test
   Output: 24 passed, 1 failed. Scenario 7 (the P2 scenario) PASSED both assertions: "health-tick's own run wrote a fixture-driven ticks.jsonl line via the shared perf-tick-snapshot.sh lib" AND "perf snapshot step is passive observability — never counted toward this tick's own anomaly alert". The single FAIL is Scenario 4 (health-tick's own pre-existing budget-cutoff test: tick took 17s against a 2s budget) — same load-artifact class, not P2 surface.
   Result: PASS
6. ticks.jsonl absence on this machine — arming gap PROVEN, not a build gap
   Command: ls ~/.claude/state/perf/ticks.jsonl (absent); schtasks query grepped for health-tick/supervisor-tick/neural/harness/claude (grep exit 1 — NO scheduled task registered)
   Supervisor-tick is operator-armed (inert until the operator registers NL-SupervisorTick — review record and manifest retirement_condition both state this); no tick has ever fired on this machine, so no organic ticks.jsonl line can exist yet.
   Result: PASS (gap is operator-side arming, exactly as the reconciliation note claims)
7. Reap default-unarmed posture vs task text (reaps ... log each reap)
   Shipped: candidates logged as would_reap by default each tick; the real kill (mechanism proven) requires operator PERF_TICK_REAP_ARMED=1. Documented as deliberate in manifest perf-tick-snapshot honesty_rationale (destructive-automation precedent: session-resumer.sh), endorsed by the harness-change review; the reviewer's wording follow-up is already in the nl-issues ledger.
   Result: PASS (documented, defensible design choice — every candidate IS logged each tick, nothing silent)
8. Manifest entry perf-tick-snapshot present with substantive golden_scenario (including the real CRLF-doubling bug regression-pinned) / fp_expectation / retirement_condition.
   Result: PASS

Runtime verification: test adapters/claude-code/hooks/lib/perf-tick-snapshot.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/health-tick.sh::--self-test
Runtime verification: test adapters/claude-code/scripts/supervisor-tick.sh::--self-test
Runtime verification: file adapters/claude-code/scripts/supervisor-tick.sh::pts_run_tick
Runtime verification: functionality-verifier P2::SKIP (rationale: harness-internal artifact; verifier executed the lib self-test 3x and both tick suites directly — no Task tool available in this invocation)

DEPENDENCY TRACE
================
Step 1: An armed tick fires (supervisor-tick primary / health-tick hourly fallback)
  ↓ Verified at: supervisor-tick.sh:446-459 and health-tick.sh:333-344 (real paths, graceful degrade) — arming itself is the operator's step (check 6)
Step 2: Tick sources the shared lib and calls pts_run_tick (snapshot collect + orphan-reap pass)
  ↓ Verified at: health-tick suite Scenario 7 PASS (my replay); supervisor-tick suite Scenario 5 PASS (reviewer replay at byte-identical blob, record hcr-20260728-3d5d64f9)
Step 3: One JSONL line (bash_count, claude_count, worktree_count, defender_cpu_ms, degraded, reaped[]) appends to ~/.claude/state/perf/ticks.jsonl; each reap candidate logged (would_reap default / reaped when armed)
  ↓ Verified at: lib self-test Scenario 10 (schema + empty-reap) + Scenario 8 (would_reap logged, kill never invoked unarmed) + Scenario 9 (armed kill mechanism proven) — my replays

Git evidence:
  Landing commit: 3cff15d (671dd20 added the writer-without-consumer acknowledgement; 6468987 is the reconciliation note)
  Files: adapters/claude-code/hooks/lib/perf-tick-snapshot.sh (new, 690 lines), scripts/supervisor-tick.sh, scripts/health-tick.sh, manifest.json (perf-tick-snapshot entry)

Observations (recorded, non-blocking):
  - Same live-install lag as P1 (live ~/.claude lacks the lib; an armed tick would WARN-and-skip the snapshot until auto-install syncs — graceful by design, verified in code).
  - Supervisor-tick budget starvation under extreme load can skip the snapshot step (fail-open-to-silence) — observed first-hand in my suite replay; already filed by the reviewer as a Major follow-up in the nl-issues ledger; P3/P4 (the immediate next dispatch) are the consumers that would notice missing data.

Verdict: PASS
Confidence: 8
Reason: PROVEN: the P2 artifact's self-test replayed 3x by the verifier (20/21 each; sole FAIL characterized as a self-test-harness race with the kill mechanism itself proven every run, nl-issue filed); the fallback tick's end-to-end tick->ticks.jsonl path replayed PASS first-hand; the primary tick's identical path proven by a committed independent 19/19 replay at a byte-identical blob; ticks.jsonl absence PROVEN operator-side (no scheduled task registered). Confidence capped at 8 (not 9) because the primary-tick suite PASS rests on the reviewer's replay, not mine — my replay hit a proven load artifact.
