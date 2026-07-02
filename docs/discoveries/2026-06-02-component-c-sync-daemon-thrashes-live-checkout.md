---
title: Component C cross-machine sync rewrites the live dev checkout mid-session
date: 2026-06-02
type: process
status: decided
auto_applied: false
originating_context: feat/event-driven-heartbeat build session (replacing the polling heartbeat scheduled task)
decision_needed: How should active manual development coexist with the Component C cross-machine-sync daemon, which performs branch checkouts / cherry-picks / resets (and triggers install.sh) on the SAME working tree a session is developing in?
predicted_downstream:
  - neural-lace/workstreams-ui (Component C cross-machine sync design)
  - adapters/claude-code/scripts/broadcast-active-session.sh
  - docs/plans/event-driven-heartbeat-2026-06-02.md (this session's work, blocked on landing)
---

## What was discovered

While building `feat/event-driven-heartbeat`, a concurrent process — the Component C
cross-machine workstreams-state sync (`broadcast-active-session.sh sync-events`,
triggered by the SessionStart "Broadcasting active-session + checking other computers"
hook and the new Stop/SessionStart sync-events wiring) — actively manipulated the
SHARED working tree and branch refs in real time:

- `git checkout` switched HEAD away from `feat/event-driven-heartbeat` → `master` →
  `sync-personal-tmp` and back, between my tool calls (confirmed via reflog
  HEAD@{0..14}).
- It `git add -A && commit`'d, absorbing my UNCOMMITTED `settings.json.template`
  `--beat` wiring into one of ITS commits (68beadb/e98deaf/9d783c6 — workstreams-tree
  work, unrelated to heartbeat), interleaving 3 foreign commits among my 3.
- It cherry-picked + reset, and HEAD advanced to new shas (9ff78f6) without my action.
- An `install.sh` run during a foreign-branch checkout reverted the LIVE harness mirror
  `~/.claude/hooks/workstreams-emit.sh` to the stale 1439-line pre-edit version (my
  beat code is 1594 lines), silently breaking the running session's heartbeat hooks.

Net effect: the git working tree, branch refs, and the live `~/.claude/` mirror are all
being rewritten by the sync daemon while a developer session is mid-build on the same
checkout. Every `git` command sees a different state.

## Why it matters

This is the classic Mode-1-concurrent-session failure (`automation-modes.md`) but caused
by an automated daemon rather than a second human session — and the daemon does
*history-rewriting* ops (checkout/cherry-pick/reset), not just file edits. Consequences:

- Uncommitted work is silently swept into unrelated commits (already happened).
- Branch HEAD moves under the developer → commits land on the wrong branch / get tangled.
- `install.sh` runs from foreign-branch checkouts corrupt the live harness mirror.
- No clean landing is possible: `git commit`/`merge`/`cherry-pick` race the daemon.

The heartbeat work itself is COMPLETE and safe — anchor commit `d67b4e7` contains the
full hook (1594 lines, all beat helpers) and passes `--self-test` 45/45 when extracted
straight from the object DB. The blocker is purely the unstable git environment.

## Options

A. **Pause the sync daemon during interactive dev.** A lock / env flag the daemon honors
   (skip sync when an interactive session is active on the checkout). Cheapest fix.
B. **Develop in a dedicated git worktree the daemon never touches.** The daemon operates
   on the main checkout only; an `isolation: "worktree"` dev tree has independent HEAD.
   But cherry-picks target shared refs — needs the daemon scoped to specific branches.
C. **Daemon syncs in a bare/mirror clone, never the dev checkout.** The most correct:
   a cross-machine sync should never `checkout`/`reset` the working tree a human develops
   in. It should fetch/push refs in a clone dedicated to sync.
D. **Daemon must never run `git add -A` / `install.sh` from a transient sync branch.**
   At minimum, scope its `add` to its own paths and never trigger install from a checkout
   it switched into.

## Recommendation

C as the durable fix (sync operates on a dedicated clone/bare mirror, never the live dev
checkout) + A as the immediate stopgap (daemon honors an interactive-session lock). B is a
viable interim. D is a must-have guard regardless of which of A/B/C is chosen — the
`git add -A` + `install.sh`-from-foreign-branch behaviors are independently dangerous.

## Decision

[pending Misha — recommend C (sync in a dedicated clone, never the dev checkout) + A (interactive-session lock stopgap) + D (never `git add -A` / `install.sh` from a transient sync branch)]

2026-07-02: absorbed as nl-overhaul task B.12 (interactive-lock stopgap now; dedicated sync clone as the Wave E/F durable fix). Operator approved.

## Preservation state (this session; the daemon fix itself is unimplemented)

- Heartbeat work preserved at anchor commit `d67b4e7` (object DB; `--self-test` OK 45/45).
- Live mirror `~/.claude/hooks/workstreams-emit.sh` re-synced from `d67b4e7` this session.
- No further git surgery attempted (would race the daemon / risk irreversible tangle).

## Investigation & interim stopgap — 2026-06-02 (read-only git; no commits)

Independent diagnostic pass (separate session). Findings refine the attribution above:

- **No automated scheduler touches the NL checkout.** Windows Task Scheduler: zero
  Claude/sync/install/heartbeat tasks (only OS built-ins). MCP/Routines scheduler: 8
  `cortex-sync-*` tasks, ALL `enabled:false`, unrelated. The conv-tree polling heartbeat
  task is absent (never registered or already removed).
- **The named culprit `broadcast-active-session.sh sync-events` is DISARMED in the LIVE
  harness.** Live `~/.claude/scripts/broadcast-active-session.sh` is the API-only version
  with NO `sync-events` subcommand; live `~/.claude/settings.json` does NOT wire
  `sync-events`. The `sync-events` subcommand + its SessionStart+Stop wiring exist ONLY in
  this feature branch's `scripts/broadcast-active-session.sh` + `settings.json.template`
  (staged, not merged, not installed). Next SessionStart/Stop on the live config will NOT
  checkout/cherry-pick/install the NL tree.
- **The CURRENT (staged) `sync-events` design is tree-safe**: it operates only on the
  dedicated clone `${WORKSTREAMS_STATE_REPO:-$HOME/dev/Personal/workstreams-state}`
  (clone/pull/push), never the NL tree, and silently no-ops when
  `WORKSTREAMS_STATE_OWNER`/`ACCOUNT` are unset. The NL-tree thrashing this doc observed
  was a PRE-FIX iteration during the live build (live mirror was flipped between versions
  by repeated `install.sh`-from-foreign-branch runs) PLUS concurrent manual reconcile.
- **Second, separate thrash vector: concurrent Claude Code sessions running manual fork
  reconcile on the shared live checkout** — `git checkout -b sync-personal-tmp / sync-bl-tmp
  / union-reconverge-*` (these branch names appear ONLY in session transcripts, no script
  creates them) and manual `sync-pt-to-personal.sh` runs (which DO `checkout -b <temp>
  mirror/master` + `cherry-pick` on the live tree). This is the Mode-1 concurrent-session
  collision (`automation-modes.md`), not a daemon. Two older CLI sessions (PIDs 24544/25652,
  ~18:55) were alive during the reflog-thrash window (16:20–19:53).

**Stopgap applied (reversible):** renamed `~/.claude/local/workstreams-sync.config` →
`workstreams-sync.config.PAUSED-2026-06-02-thrash-investigation`. This guarantees
`sync-events` stays a no-op even if this branch's wiring is accidentally merged/installed
before the design decision below is made. **Restore:** `mv` it back to
`workstreams-sync.config`.

**Status stays `pending` intentionally:** the Implementation log above records only an
investigation + a reversible stopgap. The core decision (Options A/C/D — how cross-machine
sync should coexist with active dev) is UNMADE and still rests with Misha. Do not flip Status
to decided/implemented until A/C/D is chosen.

**Do-not-merge guard:** this branch (`feat/component-c-cross-machine-sync`) must not be
merged to master nor have `install.sh` run from it until Options A/C/D are decided — merge
or install re-arms `sync-events` on every SessionStart+Stop (backgrounded). The config rename
is belt-and-suspenders; the wiring itself still needs the interactive-session lock (Option A)
and the never-`add -A`/never-`install.sh`-from-foreign-branch guard (Option D) before it is
safe to run on every session boundary.

## Implementation log

(none — the A/C/D design decision is unmade; no implementation of the daemon fix has
landed. Only the reversible interim stopgap above (config pause) has been applied. This
section flips to populated when the chosen fix is implemented.)
