# NL Observability Program — status & handoff

Last updated: 2026-07-10 (cockpit-health fix wave shipped + demonstrated).
This is the single reference for what shipped, what's live, and what remains.

## TL;DR

The **NL Observability Program is COMPLETE** (all 10 tasks verified; retro:
`docs/reviews/wave-o-retro.md`) and the cockpit is **live, healthy, and demonstrated**:
all six panes derive rc=0 at http://localhost:7733, `/api/health` reports
`any_pane_failed:false, lobotomized:false`, the reconciler polices drift, and the
doctor's rewritten `obs-cockpit-fresh` check judges it honestly (GREEN healthy, RED
up-but-lobotomized). **Master `02ff2f3`**, both remotes; the MAIN checkout now serves
master (flipped off `tmp/o4-flip` 2026-07-10; that branch still exists, unmerged work
none — it was parked at old master).

### 2026-07-09/10 incident + fix wave (addendum)

The cockpit ran a full day lobotomized (every pane failing) with zero doctor signal —
operator caught it by screenshot. Three root causes, all fixed on master `02ff2f3`
(review record: `docs/reviews/2026-07-09-cockpit-sessionstart-review.md`; findings
filed as nl-issues): (1) the derive layer spawned `bash` by BARE NAME — dead under
minimal-env spawn parents like the old logon task (registry PATH has no bash.exe dir);
now absolute-path **login-shell** spawns with HOME fallback (environment-independent);
(2) even healthy-env spawns got a profile-less bash — `nl` emitted empty stdout (jq
lives in ~/bin); same fix covers it; (3) nl.sh's spawn-cascade breaker (ceiling 10)
collided with the cockpit's own 6-concurrent batch refresh — every pane "succeeded"
empty (rc=0, a lying success); now a two-lane serial refresh + `NL_SPAWN_CEILING=32`
for cockpit children. Defense-in-depth added: `/api/health` self-reports `lobotomized`
(all panes failing + uptime>120s), launch-gui.ps1 positively identifies the server and
restarts on lobotomy (bounded), the doctor's `obs-cockpit-fresh` was de-theatered
(was double-dead: schtasks-gated on a retired task + keyed on a never-written stamp),
and the heartbeat reaper finally has a (backgrounded) production call-site.
Known-open, filed: `nl status` ~77s vs the <10s metric-1 bar (transcript-count
scaling — top perf item), the breaker's lying rc=0-empty semantics, launcher actuator
minors, `supervisor-pass` unmapped event (ADR-061 landing gap).

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
- **Logon autostart RETIRED** (2026-07-09): scheduled task `ConversationTreeUI-AutoStart`
  was unregistered (`register-autostart.ps1 -Unregister`, verified gone) as part of the
  cockpit-ensure integration below — the cockpit is now ensured-up per-session instead,
  machine-wide, so there is zero scheduled-task footprint for it.
- Both remotes tree-synced (master advanced past `f727fe5` — see below).

## FIRST TASK — integrate cockpit-ensure branch — ✅ DONE (2026-07-09)

**Integrated as `build/cockpit-sessionstart-r2` → master.** The cockpit is now
ensured-up on every NL **SessionStart** (session-tied lifecycle) instead of a boot-time
scheduled task: a one-line best-effort callsite in `session-start-digest.sh`'s
`run_digest()` (no new SessionStart entry — 8/8 cap respected, settings template
zero-diff) calls `adapters/claude-code/scripts/ensure-cockpit.sh` (idempotent wrapper
over `launch-gui.ps1 -NoBrowser`).

What shipped (base `afdedee` + review remediation `097a91a` + honesty tighten):
- **Adversarial harness-review + code-review** run (parallel, every Major
  independently verified NOT-refuted). Full record + dispositions:
  `docs/reviews/2026-07-09-cockpit-sessionstart-review.md`. Delta re-review returned
  PASS after the fixes.
- **Machine-wide launcher resolution** (the load-bearing review fix): resolves via
  `nl_repo_root()` (install config) normalized through `nl_main_checkout_root()`, so the
  cockpit is ensured from **any** project's session — not only NL-repo-rooted ones. This
  matched the machine-wide coverage of the retired logon task. **Proven live** from a
  non-NL, non-git cwd (dispatch reached the launcher; cockpit stayed HTTP 200).
- **manifest.json** `ensure-cockpit` writer entry added (was inventory-drift);
  manifest-check GREEN (111 entries). Operator kill-switch
  (`ENSURE_COCKPIT_DISABLE=1` / `~/.claude/local/cockpit-disabled`), log rotation, and
  self-test hardening (16→23 scenarios, all pass) added.
- **Logon task unregistered + verified gone** in this same integration (above).
- Coverage decision (decide-and-go, §8): **MACHINE-WIDE** — recorded in the review doc
  and the `097a91a` commit message.

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

## How to resume (branch/worktree + push mechanics)

The first task (cockpit-ensure integration) is **DONE** — there is no in-flight item
left. The residual follow-ups above are the only remaining work and all are
non-blocking (operator gate before starting any).

**Launch in a fresh WORKTREE off `master`** — in the Claude Desktop launcher keep
`Local / neural-lace / master` with the **worktree box CHECKED**. This gives a clean
isolated worktree off the latest master and sidesteps the main checkout's branch tangle
(the main checkout is parked on `tmp/o4-flip` and the `master` ref is held by another
worktree, so "main checkout on master" is not cleanly available). All integration work
(harness-review, merge, install-sync, task-registration) runs fine from a worktree —
that is how every builder in this program ran. Push to master via `git push origin
HEAD:master` (or a PR); the personal-mirror sync uses the two-account `gh auth switch`
dance documented in the global CLAUDE.md **Accounts** section (until the
gh-account-autoswitch hook is wired live). **Note:** any tracked file containing the
literal work/personal GitHub usernames trips the harness-hygiene denylist (public-mirror
hygiene) — reference the accounts via CLAUDE.md, never inline. Live `~/.claude/` sync is
`bash ~/.claude/hooks/session-start-auto-install.sh` (reads `origin/master`), **never**
`install.sh` from a worktree (it rewrites `~/.claude/local/nl-repo-path` to its own
root). Read `SCRATCHPAD.md` first (per global CLAUDE.md), then this file, then the retro.
