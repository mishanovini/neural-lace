# Deferred plans — intended-but-not-currently-active

Plans in this directory have `Status: DEFERRED`. They are **the plan-level
backlog**: work that is *still intended to be built* but is **not currently
active**. They are NOT done — do not treat them as archived/finished.

## Why a separate directory (not archive/)

`docs/plans/archive/` is for plans that are **done with**: `COMPLETED`,
`ABANDONED`, `SUPERSEDED`. Burying a *paused-but-intended* plan there loses the
"still needs building" signal (the smell Misha flagged 2026-06-04).

The plan lifecycle splits the destination by status (ADR 052):

| Terminal status | Meaning | Destination |
|---|---|---|
| `COMPLETED` | work done | `docs/plans/archive/` |
| `ABANDONED` | won't build | `docs/plans/archive/` |
| `SUPERSEDED` | replaced | `docs/plans/archive/` |
| `DEFERRED` | **intended, paused** | `docs/plans/deferred/` ← here |

## How plans get here / leave here

- **Arrive:** flipping a plan's `Status:` to `DEFERRED` (via Edit) fires
  `plan-lifecycle.sh`, which `git mv`s it here. The SessionStart
  `plan-status-archival-sweep.sh` is the safety net for sed-flipped statuses.
- **Resume (re-activate):** flip the plan's `Status:` back to `ACTIVE` and
  `git mv` it back to `docs/plans/<slug>.md`. It re-enters the active set.
- **Truly drop:** flip to `ABANDONED` (then it archives).

## Discoverability

`find-plan-file.sh` searches active → **deferred** → archive. These plans are
visible roadmap, not lost. (A SessionStart surfacer for this directory is the
intended follow-up so deferred plans stay nudged like the backlog.)
