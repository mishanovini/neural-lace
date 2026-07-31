# Estate coordination — full

> Compact: doctrine/estate-coordination.md

Mechanizes the 2026-07-04 manual estate-coordination run (NL-FINDING-031),
recorded live in the main checkout's `SCRATCHPAD.md` `## COORDINATION ORDER` /
`COORD UPDATE` sections. Full protocol: `skills/coordinate-estate/SKILL.md`.

## The one rule: file-based channels ONLY

`send_message` prompts the TARGET session's user for confirmation on **every**
call (verified live, 2026-07-06) — it is a per-message-confirmed nudge for a
session someone is actively watching, never an unattended orchestration
primitive. A queued message to an autonomous satellite sits undelivered
indefinitely. Coordination state lives in files both sessions read: the main
checkout's `SCRATCHPAD.md` coordination section (durable, append-only, polled
by digest/resumer) and `nl-issue.sh` (re-homing target for orphaned work).

**Corollary:** autonomous satellites must be **orchestrator-owned Agent tool
worktree dispatches**, not independently-launched interactive sessions. An
interactive session can hit an unattended permission dialog and wedge with no
channel back — the 2026-07-04 run lost three satellites this way (empty
worktrees, nothing to lose, terminal state = an unanswered dialog). An
Agent-tool dispatch runs to completion or reports back in the same turn; there
is no dialog surface to wedge on.

## Classification (session inventory via `list_sessions`)

`active` (running or active <2h) · `stalled>2h` (idle, no terminal marker, no
pending dialog — nudge/re-dispatch) · `wedged-undeliverable` (idle + an
unanswered permission dialog as the terminal state — cannot be revived by any
message; re-home its work instead) · `superseded` (its fix already landed
elsewhere — grep master + all `origin/build/*`/`origin/claude/*` branches
BEFORE dispatching or trusting a session's self-report, per the 2026-07-04
duplicate that was caught this way).

## Re-homing orphans

`wedged-undeliverable` sessions with real unlanded work: one line via
`nl-issue.sh "orphaned from wedged session <id>: <what it was doing>"` — never
try to message a wedged session (it cannot answer) and never edit its worktree
from outside it.

## Freeze-window protocol

Declare `FREEZE STATUS: PENDING` in the coordination section naming the wait
condition → satellites land-or-hold → flip `FREEZE STATUS: ACTIVE` once
satellites report (or a named timeout) → cutover owner is the ONLY session
that pushes master while ACTIVE → cutover owner writes `CUTOVER-DONE @ <sha>`
→ coordinator independently verifies the sha is really on master (never trust
the self-report alone, constitution §1) → freeze lifts.

## Spawn-time supersession check

Before every autonomous dispatch: `git fetch origin master --quiet && git log
--oneline origin/master | grep -i "<keyword>"` plus a scan of sibling
`origin/build/*`/`origin/claude/*` branches. A match means don't dispatch —
fold in the existing result or note the other owner in the coordination
section instead.
