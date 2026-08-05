# Single-flight/recursion guard + HALT/drain — compact

> Spec of record: `docs/plans/harness-execution-redesign-2026-08.md` Task 1 (Stage 0a).
> Full: `single-flight-halt-runbook-full.md` (every finding — HR-F1/F7/F10/F11 — schedule-
> manifest schema, matcher-narrowing detail, known live-reconcile gap).
> Applies: any "heavy entry point" sourced repeatedly per session/tick — `harness-doctor.sh`,
> `session-start-digest.sh`, `coord-sync.sh`, `supervisor-tick.sh`, `health-tick.sh`.

## Why this exists

The 2026-08-02 self-DoS incident's root cause was a wiring-marker-only guard that only debounces
the ONE call site that remembers to set it. **The guard lives in the library, unconditionally,
not in the wiring.**

## The library: `hooks/lib/single-flight-lib.sh`

```
sf_guard <name> <ttl_seconds>   -> rc 0 RUN, rc 1 SKIP (HALT, recursion, or single-flight)
sf_release <name>               -> clears this process's recursion guard + cross-process lock
```

1. **HALT/drain** (checked first) — `${SF_HALT_DIR:-$HOME/.claude/state/single-flight}/HALT`,
   its OWN dir, independent of `SF_STATE_DIR` (the lock dir) so a scoped-lock caller still gets
   HALT for free (HR-F11).
2. **Recursion guard** (zero I/O env var) — **resident-loop callers** (`--daemon` mode) MUST pair
   every acquire with `sf_release` or every pass after the first silently no-ops forever (HR-F1;
   wedged `nl-maintenance.sh --daemon` after one tick).
3. **Cross-process single-flight** (mkdir + TTL) — debounces unrelated processes on `<name>`
   within `<ttl_seconds>`.

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

## Flap-stop — distinct from HALT/drain, do not confuse the two

`nl-maintenance.sh`'s `--watchdog` also carries a SEPARATE guard: if it relaunches the daemon
`NM_FLAP_THRESHOLD` times (default 4) inside `NM_FLAP_WINDOW_SECONDS` (default 3600s), it STOPS
resurrecting, writes `state/nl-maintenance/flap-state.json`, and every later fire is a log-only
no-op until `nl-maintenance.sh --reset-flap`. Unlike HALT (an operator's deliberate, reversible-
by-file-delete stop gesture), a flap-stop is the watchdog's OWN automatic response to a daemon
that cannot stay up — it means something is actively crash-looping, not that anyone asked it to
stop. `harness-doctor.sh`'s `maintenance-daemon-flap` check REDs while tripped (never silent).
Full derivation of the threshold/window numbers: `nl-maintenance.sh`'s own header comment above
`_nm_flap_window_seconds`.

## Chesterton's Fence + mechanized budgets

`hook-reentry-guard.sh` / `sessionstart-singleflight.sh` are unchanged, still wired — belt, never
braces, now that `sf_guard` is primary. Deliberate change: `sf_guard` also single-flights
EXPLICIT/manual reruns — an old-contract self-test must set `SF_DISABLE=1`.
`schedule-manifest.json`'s cadence check (WARN when cadence < 2x measured cycle) and the
Bash-hook-count budget (WARN above 6) carry a stored `warn_since`/`red_after` date (HR-F7) — the
doctor flips WARN to RED on its own, no operator action.

## SessionStart matcher narrowing

The two heaviest hooks moved from the blanket `""` matcher to `"startup|clear"` — `resume` never
dispatches them. **Known gap:** the auto-install merge is additive-only and does not migrate a
live machine's existing wiring; see the full runbook for the manual reconcile.
