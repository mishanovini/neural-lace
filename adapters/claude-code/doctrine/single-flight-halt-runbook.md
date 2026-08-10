# Single-flight/recursion guard + HALT/drain — compact

> Spec of record: `docs/plans/harness-execution-redesign-2026-08.md` Task 1 (Stage 0a).
> Full: `single-flight-halt-runbook-full.md` (HR findings, schedule-manifest schema,
> matcher detail, flap-stop derivation, live-reconcile gap).
> Applies: any heavy entry point sourced repeatedly per session/tick.

## Why this exists

The 2026-08-02 self-DoS: a wiring-marker-only guard debounces only the call site that
remembers to set it. **The guard lives in the library, unconditionally, not in the wiring.**

## The library: `hooks/lib/single-flight-lib.sh`

```
sf_guard <name> <ttl_seconds>   -> rc 0 RUN, rc 1 SKIP (HALT, recursion, or single-flight)
sf_release <name>               -> clears this process's recursion guard + cross-process lock
```

1. **HALT/drain** (checked first) — `${SF_HALT_DIR:-$HOME/.claude/state/single-flight}/HALT`,
   its OWN dir, independent of `SF_STATE_DIR`, so scoped-lock callers get HALT free (HR-F11).
2. **Recursion guard** (zero-I/O env var) — resident-loop callers MUST pair every acquire with
   `sf_release` or every pass after the first silently no-ops forever (HR-F1).
3. **Cross-process single-flight** (mkdir + TTL) — debounces unrelated processes on `<name>`.

Fail-open on every internal error path — HALT is the only mechanism allowed to deliberately
block real work. Bypass: `SF_DISABLE=1`.

## HALT/drain — the one gesture

```
mkdir -p ~/.claude/state/single-flight && printf '%s %s\n' "$(date +%s)" "<reason>" \
  > ~/.claude/state/single-flight/HALT   # stop the maintenance layer NOW
rm -f ~/.claude/state/single-flight/HALT # resume
```

DRAIN not KILL: in-flight work finishes, nothing new arms. Every tick wrapper checks
`sf_halt_active` first and logs a drain notice (durable log + stdout, always both).

## Flap-stop — distinct from HALT/drain

`--watchdog` stops resurrecting after `NM_FLAP_THRESHOLD` (4) relaunches inside
`NM_FLAP_WINDOW_SECONDS` (5400s since 2026-08-10), writes
`state/nl-maintenance/flap-state.json` (doctor REDs while tripped), and requires the one
explicit `--reset-flap`. A flap-stop is the watchdog's automatic crash-loop response —
never an operator gesture. Full detail + number derivation: -full.md §Flap-stop and
`nl-maintenance.sh`'s header above `_nm_flap_window_seconds`.

## Chesterton's Fence + mechanized budgets

`hook-reentry-guard.sh` / `sessionstart-singleflight.sh` stay wired — belt, never braces.
`sf_guard` also single-flights EXPLICIT reruns — old-contract self-tests set `SF_DISABLE=1`.
The cadence check and Bash-hook-count budget carry stored `warn_since`/`red_after` dates
(HR-F7) — the doctor flips WARN to RED on its own.

## SessionStart matcher narrowing

The two heaviest hooks use `"startup|clear"`, never `resume`. **Known gap:** the additive
auto-install merge does not migrate existing live wiring — manual reconcile per -full.md.
