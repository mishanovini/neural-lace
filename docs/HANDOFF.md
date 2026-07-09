# NL Observability Program — status & handoff

Last updated: 2026-07-09 (handoff for a Claude-account switch; same machine/repo).
This is the single reference for what shipped, what's live, and what remains.

## TL;DR

The **NL Observability Program is COMPLETE** — all 10 tasks (O.0–O.9) verified by an
adversarial task-verifier, merged to **master `f727fe5`** (both remotes), plan archived
`Status: COMPLETED`. The full record with measured numbers is the retro:
`docs/reviews/wave-o-retro.md`. One small follow-on (a cockpit auto-start refinement) is
in flight on a pushed branch; a short list of non-blocking residuals is filed. Nothing
is broken; the estate is at a clean stopping point.

## What shipped (DONE, on master f727fe5)

- The `nl` CLI answers all six operator questions from ground truth, each <10s:
  `nl status | needs-me | why | costs | shipped | health | backlog`.
- The Workstreams UI is rebuilt as a thin six-question view over derived truth
  (cockpit), the old event-sourced trust path (both gates + item-extraction writers)
  retired to `attic/` — closing NL-FINDING-024 at the root.
- Signal ledger extended to 10 lifecycle/spawn/turn-trace event types with a
  100%-coverage consumer-map invariant; per-session heartbeats + reaper; six doctor
  pipeline-health checks; estate-coordination skill; backlog accountability loop with
  build-escalation + dispositioned-in-flight state.
- O.5 (ntfy phone push) was **descoped by operator** (no phone observability).
- Decisions: `docs/decisions/060-wave-o-observability-architecture.md`.

## Live now on this machine

- **Cockpit server up on http://localhost:7733** (rebuilt derive-cache server).
- **Logon autostart registered**: scheduled task `ConversationTreeUI-AutoStart`
  (AtLogon, hidden, restart-3×, points at the rebuilt `server.js`). NOTE: this becomes
  redundant once the in-flight SessionStart integration lands — see below.
- Both remotes tree-synced at `f727fe5`.

## FIRST TASK for the new session — integrate the finished cockpit-ensure branch

**`build/cockpit-sessionstart` @ `afdedee` (pushed to origin) — BUILT + VERIFIED, not
yet merged.** Operator's better design (2026-07-09): the cockpit is ensured-up on every
NL **SessionStart** (tied to session lifecycle) instead of a boot-time scheduled task.
As-built: a one-line best-effort callsite in `session-start-digest.sh`'s `run_digest()`
(no new SessionStart entry — 8/8 cap respected, settings template zero-diff) calling a
new `adapters/claude-code/scripts/ensure-cockpit.sh` (idempotent wrapper over
`launch-gui.ps1 -NoBrowser`). Guards all present: Windows-only, skip-under-
HARNESS_SELFTEST, MAIN-checkout resolution via nl-paths.sh, `nohup … & disown` non-
blocking (proven ~1s return), tolerate-absent. Self-test 16/16; `session-start-digest.sh`
baseline unchanged (70/71 — the 1 is the known S2 flake). Real Windows dispatch verified
live against the running cockpit.

**To integrate (this is the new session's warm-up — confirms the handoff works):**
(1) **harness-review the diff** (required — it's a core-hook change; run the
harness-reviewer agent); (2) if PASS, merge `origin/build/cockpit-sessionstart` to
master + push both remotes; (3) run `install.sh`; (4) then **unregister the now-redundant
logon task**: `powershell -File "neural-lace\workstreams-ui\scripts\register-autostart.ps1"
-Unregister`. After that the cockpit auto-starts with every session and there is zero
scheduled-task footprint for it.

## Residual follow-ups (all filed; none blocking)

- `cold-reader-lint` decision-block regex false-fires on negation ("no decision needed
  here") — WARN-only (nl-issue filed).
- `session-start-digest` S2 self-test reads live `unresolved-gaps.jsonl` (fixture-
  isolation leak; nl-issue filed).
- `NL-session-resumer` scheduled task disabled / Last Result -1 (E.7/ops decision).
- `gh-account-autoswitch` hook built + on master but NOT wired into live
  `settings.json` (the auth-stuck fix; wire with the jq command in the retro/completion
  report — classifier blocks the agent from editing live settings).
- `session-heartbeat reap` has no scheduled call-site (backlog HARNESS-PERF-O3-HB).
- **`session-start-digest.sh` hangs ~90s on real invocation** — root-caused to
  `feed_git_freshness` piping into `session-start-git-freshness.sh` (works standalone in
  ~4s, hangs when piped as the digest does it). Pre-existing (confirmed via git stash);
  spawned as `task_d8072e25`. This slows every session start and is worth prioritizing —
  the cockpit-ensure callsite completes before it, so it is unaffected, but the digest
  itself is degraded.
- Optional: a codebase-wide "second-source-of-truth" audit (the wave's FAIL class was
  always a fact computed two ways; instances found are fixed, but a sweep for others is
  available on request — not scheduled).

## How to resume (branch/worktree + prompt)

**Launch in the MAIN checkout** (NOT a worktree): `C:\Users\misha\dev\Pocket
Technician\neural-lace`. It is currently on branch `tmp/o4-flip`, whose content ==
`origin/master`. First actions in the new session: `git fetch origin && git merge
--no-edit origin/master` (sync), then continue committing to master via `git push
origin HEAD:master` (the pattern used all program). For personal-mirror sync do the
`gh auth switch -u mishanovini` → push → `gh auth switch -u MishaPT` dance (until the
gh-account-autoswitch hook is wired live). Read `SCRATCHPAD.md` first (per global
CLAUDE.md), then this file, then the retro.

**Suggested resume prompt** (paste into the new Fable session):

> You are resuming as the NL Observability Program orchestrator on this machine
> (`C:\Users\misha\dev\Pocket Technician\neural-lace`, main checkout). Read
> `SCRATCHPAD.md`, then `docs/HANDOFF.md`, then `docs/reviews/wave-o-retro.md`. The
> program is COMPLETE on master `f727fe5`; the cockpit is live on :7733. Your immediate
> job is the one in-flight item in HANDOFF.md — verify + harness-review + integrate
> `build/cockpit-sessionstart @ afdedee` (SessionStart cockpit-ensure), then unregister
> the redundant `ConversationTreeUI-AutoStart` logon task. After that, the residual
> follow-ups in HANDOFF.md are available but non-blocking — check with me before
> starting any of them. Keep me updated with what's done and what needs me.
