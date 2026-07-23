# Recurrence Diagnosis — CPU Heaviness Returned (2026-07-20, ~1 week after the 2026-07-13 profile)

**Companion to:** [2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md](2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md)
**Trigger:** Operator saw performance recover after the 2026-07-13 diagnostic, then degrade again a week
later. Question: *same issues, or new?* **Answer: BOTH — the old ones were never structurally fixed
(only documented + backlogged), and a NEW failure mode (runaway recursive self-spawning chains) is now
layered on top.** Live evidence captured from `Get-CimInstance Win32_Process` on 2026-07-20 ~17:13.

## Why the relief was temporary
The 2026-07-13 session was **diagnostic only** — it produced the lesson doc, a backlog row
(`SESSIONSTART-SINGLEFLIGHT-01`), and nl-issues, but **shipped no code**. The improvement the operator
saw was transient (killing the runaway `find` at that moment + the session-start storm settling), not a
durable fix. Nothing structural changed, so the same classes regenerate. **Confirmed: no single-flight
lock was built; the disk-wide-find agent behavior persists; Defender real-time protection is still ON
(`DisableRealtimeMonitoring = False`); exclusion list unverifiable without admin.**

## SAME issues, still live (the 2026-07-13 classes, unfixed)

1. **Disk-wide `find` eating ~13% of a core (repeat).** Live process PID 14916:
   `"C:\Program Files\Git\usr\bin\find.exe" / -iname scope-enforcement-gate*` — a full **C:\ drive**
   scan for a hook file, issued ad-hoc by a session instead of `Glob`/known path. Exactly the class
   flagged 07-13. (Killed on sight this session; see relief below.)
2. **Fork storm + Defender scanning.** Antimalware at ~16.7% is Defender scanning the process churn.
   Same root cause; still no single-flight lock, still no confirmed exclusions.

## NEW issue — runaway recursive self-spawning chains (the real reason it's WORSE now)

The live snapshot shows **dozens** of bash processes that are NESTED copies of the same script spawning
itself over a 5–7 minute window — a slow fork-multiplication, not a one-shot storm. Observed chains:

- **`session-start-digest.sh --self-test`** — ~15+ instances, parent→child chains where a
  `session-start-digest --self-test` is itself the PARENT of another `session-start-digest --self-test`
  (e.g. PID 5832→17528, 2784→19700, 26920→26772). **A `--self-test` should not be running on normal
  session start at all, let alone recursively.** Prime suspect for a self-referential spawn bug.
- **`worktree-hygiene-sweep.sh --stranded /…/<downstream-product>/prod-monitor`** — long nested chain
  (16192→41396→36376→13656→22156…) spanning 4:06→5:13, each spawning the next. Runaway.
- **`spec-freeze-gate.sh`** nested (34520→27140→34712→31596); **`prod-monitor-health-probe.sh`** nested
  (20940→54560→28732→5536); **`nl.sh status/costs/backlog --json`** (cockpit polling) multiple.

**Mechanism (REFINED after reading `session-start-digest.sh`):** NOT unbounded recursion. The
`--self-test` path is a **genuinely fork-heavy multi-scenario test**: it runs 15+ scenarios, invokes
member hooks' OWN `--self-test`, and even does `git commit` inside temp fixtures (lines 2158, 2250+),
so ONE `session-start-digest.sh --self-test` legitimately fans out into dozens of child bash
processes. What multiplies it: something on the live machine is **running these self-test sweeps
repeatedly** (candidate origins: a `harness-doctor.sh --full` sweep — `--quick`, which I DID see
running, explicitly skips self-tests; a scheduled verification tick; or `ensure-cockpit.sh`), and with
5 concurrent sessions each potentially triggering one, the fan-out stacks. The parents (PID 9268/7844)
were already gone when traced — consistent with short-lived spawn-and-exit sweeps, not a persistent
fork bomb. There is already an NL-FINDING-040 re-entrancy guard in the digest RUN path (line 2285),
but the `--self-test` entry (line 2252) bypasses it. **Open question for the fix: what invokes
`session-start-digest.sh --self-test` on the live machine, and why repeatedly** — that origin is the
thing to gate.

## Contributing amplifier: concurrency
29 Claude processes + 5 active worktrees (per SessionStart broadcast) + scheduled monitors
(prod-monitor-health-probe every ~tick, workstreams-emit heartbeat). Each session multiplies the per-tool
hook spawns from the 07-13 profile. More sessions than a week ago = higher baseline floor.

## Immediate relief taken this session
- Killed the runaway disk-wide `find` (PID 14916, `find / -iname scope-enforcement-gate*`).
- (Did NOT mass-kill the recursive chains — they belong to other live sessions/scheduled tasks;
  blindly killing them risks corrupting concurrent work, per the 2026-07-11 bulk-mutation lesson.
  The fix is structural, below.)

## What must actually change (promote from backlog to BUILD)
1. **Trace + fix the `session-start-digest.sh --self-test` recursion** — highest priority; a hook that
   spawns itself is a fork bomb with a slow fuse. Add a re-entrancy guard (env-var sentinel:
   `[ -n "$NL_DIGEST_SELFTEST" ] && exit 0; export NL_DIGEST_SELFTEST=1`) and confirm `--self-test`
   is not wired into the live SessionStart path.
2. **Same re-entrancy guard for `worktree-hygiene-sweep.sh`, `spec-freeze-gate.sh`, `prod-monitor-health-probe.sh`.**
3. **Ship `SESSIONSTART-SINGLEFLIGHT-01`** (single-flight lock) — no longer optional; it's the
   containment for all of the above.
4. **`find /` warn-hook** (rec 6 from 07-13) — catch disk-wide finds at PreToolUse, suggest `Glob`.
5. **Defender exclusions** for `~/.claude/`, Git Bash, repo roots (operator/admin action).

## Bottom line for the operator
Not a mystery and not a single new bug: it's the **same unfixed 07-13 classes** plus a **new recursive
self-spawn multiplier**, amplified by **more concurrent sessions**. The durable fix is to BUILD the
backlogged items (esp. the re-entrancy guards + single-flight lock), not re-diagnose. Recommend a
scoped build plan.
