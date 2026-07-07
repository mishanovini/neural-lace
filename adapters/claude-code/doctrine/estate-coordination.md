# Estate coordination — compact
> Enforcement: Pattern — self-applied via `skills/coordinate-estate.md`. No hook.
> Full: doctrine/estate-coordination-full.md
> Applies: any session managing/dispatching multiple concurrent sessions across
> the estate (this machine's other checkouts/worktrees), and any freeze-window
> cutover needing exclusive master access.

Mechanizes the 2026-07-04 manual estate-coordination run (NL-FINDING-031),
recorded live in the main checkout's `SCRATCHPAD.md` `## COORDINATION ORDER` /
`COORD UPDATE` sections. Full protocol: `skills/coordinate-estate.md`.

## The one rule: file-based channels ONLY

`send_message` prompts the TARGET session's user for confirmation on **every**
call (verified live, 2026-07-06) — it is a per-message-confirmed nudge for a
session someone is actively watching, never an unattended orchestration
primitive. Coordination state lives in files both sessions read:
`SCRATCHPAD.md`'s coordination section (durable, append-only, polled by
digest/resumer) and `nl-issue.sh` (re-homing target for orphaned work).

**Corollary:** autonomous satellites must be **orchestrator-owned Agent tool
worktree dispatches**, not independently-launched interactive sessions — an
interactive session can hit an unattended permission dialog and wedge with no
channel back (see doctrine/estate-coordination-full.md for the 2026-07-04
loss of three satellites this way). An Agent-tool dispatch runs to completion
or reports back in the same turn; there is no dialog surface to wedge on.

## Classification, re-homing, freeze-window, supersession check

Session classification (`active` / `stalled>2h` / `wedged-undeliverable` /
`superseded`), orphan re-homing via `nl-issue.sh`, the freeze-window cutover
protocol, and the spawn-time supersession check (grep master + sibling
branches before dispatching) are all detailed in
doctrine/estate-coordination-full.md — read it before running a freeze
window or classifying a stalled session for the first time.
