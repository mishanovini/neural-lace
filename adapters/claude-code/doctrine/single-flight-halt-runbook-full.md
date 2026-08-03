# Single-flight/recursion guard + HALT/drain — full runbook

This is the detail companion to `single-flight-halt-runbook.md` (the compact,
capped at 3000 bytes by `evals/golden/rules-index-coverage.sh`). It holds the
complete operational detail — every finding (HR-F1, HR-F7, HR-F10, HR-F11),
the schedule-manifest schema, and the known gaps — trimmed out of the compact
on 2026-08-03 to bring the compact back under the cap. The compact's summary
stands alone for the load-bearing rule; this file is the full mechanism.

# Single-flight/recursion guard + HALT/drain — runbook

> Spec of record: `docs/plans/harness-execution-redesign-2026-08.md` Task 1 (Stage 0a);
> `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` §2 invariants 4 and 11.
> Applies: any script that becomes a "heavy entry point" (does real filesystem/git/subprocess
> work) sourced repeatedly per session or per tick — currently `harness-doctor.sh`,
> `session-start-digest.sh`, `coord-sync.sh`, `supervisor-tick.sh`, `health-tick.sh`.

## Why this exists

The 2026-08-02 self-DoS incident's root cause included a wiring-marker-only guard
(`NL_SESSIONSTART_ORIGIN`) that only debounces the ONE call site that remembers to set it —
a resume-origin invocation (or any future caller) that doesn't set the marker sails straight
through, and 16 concurrent nested doctor chains follow. Invariant 4 fixes the CLASS, not the
instance: **the guard lives in the library, unconditionally, not in the wiring.**

## The library: `adapters/claude-code/hooks/lib/single-flight-lib.sh`

Two independent mechanisms, one function:

```
sf_guard <name> <ttl_seconds>
  rc 0 -> caller SHOULD RUN
  rc 1 -> caller SHOULD SKIP (HALT, recursion, or single-flight — always a one-line
          stderr notice AND a best-effort ledger_emit("single-flight", "skip", ...) call)
```

1. **HALT/drain** (invariant 11) — checked first. `sf_halt_active` / `sf_halt_set [reason]` /
   `sf_halt_clear` / `sf_halt_reason`. One file: `${SF_HALT_DIR:-$HOME/.claude/state/single-flight}/HALT`
   — its OWN canonical directory, independent of `SF_STATE_DIR` (HR-F11, see below).
2. **Recursion guard** (invariant 4, zero I/O) — an exported env var
   (`_SF_ACTIVE_<sanitized-name>`) that a genuine nested subprocess invocation inherits. Catches
   "this same process tree is already running this named entry point again" with no filesystem
   access at all.
3. **Cross-process single-flight** (invariant 4, mkdir + TTL-aged owner stamp) — the SAME
   portable mechanics as the pre-existing `sessionstart-singleflight.sh` (mkdir is atomic;
   staleness falls back from a stored epoch to directory mtime on MSYS where `stat`/`flock` are
   unreliable). Debounces concurrent, unrelated (non-descendant) processes calling the same
   `<name>` within `<ttl_seconds>`.

Fail-open on every internal error path (unwritable state dir, missing `find`, a lost mkdir
race) — HALT is the only mechanism allowed to deliberately block real work. Bypass:
`SF_DISABLE=1` (every self-test that needs to isolate itself from this guard uses it).

### `sf_release` — releasing a resident-loop guard (HR-F1, 2026-08-03)

`sf_guard`'s recursion guard is an exported env var that nothing clears automatically — a
**run-to-exit assumption**. For a caller that acquires once and then runs to completion, process
exit clears it for free. For a caller that lives inside a resident loop (the SAME process calling
`sf_guard` for the SAME `<name>` on every pass — e.g. a `--daemon` mode), that assumption breaks:
pass 1 acquires and exports the var; every later pass in that same process sees it already set,
hits the recursion branch, and skips — forever. This is exactly what happened to
`nl-maintenance.sh`'s `--daemon` mode (2026-08-03 harness review, finding HR-F1): it ticked
exactly once, then silently wedged on its own guard for the rest of its life, while the watchdog
kept relaunching new daemons on top of the stuck one (see "Daemon lifecycle" below).

```
sf_release <name>
  Clears the recursion-guard env var and removes the cross-process mkdir lock for <name>.
  Idempotent — a second call, or a call for a name this process never itself acquired, is a
  silent no-op. Ownership-safe — it only acts when the recursion var IT set is still 1, so it
  can never tear down a DIFFERENT process's active single-flight hold.
```

**The rule**: any `sf_guard` call site inside a resident loop MUST pair every acquire with an
`sf_release` once that pass's guarded work is done — `guard -> work -> release`, every pass. A
call site that runs to process exit after a single guard does not need to call `sf_release` at
all. Get this wrong and the symptom is silent and easy to miss in review: the first pass works,
every later pass quietly no-ops.

## Daemon lifecycle: `nl-maintenance.sh --daemon` / `--watchdog` (HR-F1)

`--daemon` loops `sf_guard "nl-maintenance-tick" -> tick body -> sf_release "nl-maintenance-tick"`
once per pass (the resident-loop pattern above), so every pass writes a fresh heartbeat instead of
only the first. `run_daemon` also writes its own pid to `daemon.pid` on startup.

`--watchdog` (the one recurring OS task, fired every 300s by `install-maintenance-task.ps1`) now
reads `daemon.pid` before relaunching on a stale heartbeat, and verifies the named pid's command
line actually names `nl-maintenance` + `--daemon` before ever killing it:

- **Verification order**: try `/proc/<pid>/cmdline` first (present under MSYS2/Git-Bash on
  Windows and on Linux); fall back to `ps -fp <pid>` (`-f` is required — a bare `ps -p` on this
  repo's MSYS2 `ps` prints only the executable path in `COMMAND`, never the args, which would
  make identity verification impossible).
- **Match**: kill the verified-stale daemon, then relaunch.
- **Mismatch** (missing pid file, dead pid, or a live pid whose command line doesn't match —
  e.g. Windows reused the pid for an unrelated process): **log-and-skip, never kill**, then
  relaunch anyway. An unverified kill is unbounded harm (an innocent process dies); leaving a
  genuine stale daemon alive for one extra relaunch cycle is bounded harm — and now self-healing,
  because that daemon's own `sf_release`-per-pass fix means it keeps ticking correctly instead of
  wedging, so two briefly-coexisting daemons is a transient, self-resolving condition, not
  unbounded accumulation.
- Under `HARNESS_SELFTEST=1`, both the kill and the relaunch are stubbed (logged, never
  performed) — mirrors the existing relaunch-stub contract exactly.

`nl-maintenance.sh --self-test`'s S11 exercises the daemon loop under the REAL guard (no
`SF_DISABLE`) across 3 passes and asserts >= 2 distinct heartbeat writes plus the absence of any
`recursion detected` message — the previous version of S11 ran under `SF_DISABLE=1`, which made it
structurally incapable of catching HR-F1 at all.

## Relationship to the two guards that already existed — Chesterton's Fence

- `hooks/lib/hook-reentry-guard.sh` (`NL_HOOK_REENTRY`) and
  `hooks/lib/sessionstart-singleflight.sh` (`ss_singleflight`, gated on
  `NL_SESSIONSTART_ORIGIN`) are **unchanged, still wired, still tested**. Neither is deleted or
  weakened.
- Per invariant 9 ("retire-before-extend, mechanized"), those two markers become **belt, never
  braces**: `sf_guard` is now the PRIMARY, unconditional layer; the marker-gated mechanisms are
  additional, narrower defense-in-depth that happens to also catch the marker-carrying cases.
- **A real, deliberate behavior change**: `sf_guard` also single-flights EXPLICIT/manual
  reruns (an operator typing `harness-doctor.sh --quick` twice within the TTL gets an honest
  one-line skip). The old marker-gated mechanisms never did this. This is intentional — the old
  contract's "explicit invocations are never suppressed" promise was a property of the OLD,
  narrower mechanism; the new unconditional guard's promise is broader by design (invariant 4's
  whole point is "don't rely on the caller to identify itself"). Any pre-existing self-test that
  specifically validates the OLD mechanism's isolated contract sets `SF_DISABLE=1` on its own
  invocation to avoid being confounded by the new, independent guard — see
  `harness-doctor.sh`'s `9-ssf-explicit-invocation-never-suppressed-BY-SSF` scenario (HR-F10,
  2026-08-03 harness review, renamed to say what it now actually validates — "never suppressed"
  was false at system level once `sf_guard` joined the mix) and `session-start-digest.sh`'s `S20c`
  scenario for the pattern.

## HALT path is canonical, not scopable (HR-F11, 2026-08-03 harness review)

`sf_guard`'s HALT check resolves via `SF_HALT_DIR` — its OWN directory, defaulting to
`$HOME/.claude/state/single-flight` — **independent of `SF_STATE_DIR`**, the (optionally scoped)
directory used for the cross-process LOCKS. Before this split, HALT shared `SF_STATE_DIR`'s
resolution, so a caller that scopes its locks away from the default — `nl-maintenance.sh`'s
tick/watchdog guards do exactly this (`SF_STATE_DIR="$(_nm_state_dir)/single-flight"`) — also,
silently, moved WHERE the operator's one-gesture HALT below had to be written to reach that
specific guard call. The "touch one file at the default path" gesture always worked in practice
only because `nl-maintenance.sh`'s tick body ALSO carries its own separate, unscoped
`sf_halt_active` check inside `_nm_tick_body` (a second, redundant read of the default HALT path)
— a coincidence of two checks, not a guarantee, and any FUTURE scoped `sf_guard` call site without
that redundant belt-and-suspenders check would have silently been unreachable by the one-gesture
HALT.

`SF_HALT_DIR` and `SF_STATE_DIR` default to the identical directory, so any caller that never sets
either sees NO behavior change from this fix. Only a caller that scopes `SF_STATE_DIR` (moving its
locks) without also scoping `SF_HALT_DIR` is affected — and only for the better: its `sf_guard`
call now sees the canonical HALT directly, the very first time it checks, with no dependence on a
second unscoped check elsewhere in the caller's own code. Self-tests that exercise HALT must now
export `SF_HALT_DIR` explicitly (alongside the pre-existing `SF_STATE_DIR` sandbox override) —
`single-flight-lib.sh --self-test`'s own setup does this.

## HALT/drain — the "one gesture"

```
# stop the maintenance layer (coord-sync, supervisor-tick, health-tick tick wrappers, and
# any script sourcing sf_guard) right now:
mkdir -p ~/.claude/state/single-flight && printf '%s %s\n' "$(date +%s)" "<your reason>" > ~/.claude/state/single-flight/HALT

# resume:
rm -f ~/.claude/state/single-flight/HALT
```

Semantics: DRAIN, not KILL. A tick already mid-flight finishes; nothing NEW arms while HALT is
set. `coord-sync.sh` / `supervisor-tick.sh` / `health-tick.sh` each check `sf_halt_active`
as the very first line of their real-work function and, if set, log a drain notice (via BOTH
their own durable per-tick log AND a plain stdout echo — some tick loggers, e.g.
`supervisor-tick.sh`'s `_st_log`, write ONLY to a file, never stdout, so the HALT arm always
echoes explicitly too) and return 0 without doing any work. `harness-doctor.sh` and
`session-start-digest.sh` get the same check for free through `sf_guard` itself (HALT is
checked before the recursion/single-flight tiers).

A forgotten HALT cannot look green: invariant 5 (output-freshness health, Stage 1) is the
counter for the resident-maintenance-core case; for the current per-tick scripts, the drain
notice is the visible signal (durable log line + stdout).

## Schedule manifest: `adapters/claude-code/config/schedule-manifest.json`

Bootstrap of the aggregate artifact invariant 2 requires ("cadence >= 2x measured cycle time
for every recurring mechanism, doctor-enforced"). Schema:

```jsonc
{
  "schema_version": 3,
  "cadence_check": {
    "mode": "warn", "ratio_floor": 2,
    "warn_since": "2026-08-03", "red_after": "2026-08-17"
  },
  "budget_check": {
    "mode": "warn",
    "warn_since": "2026-08-03", "red_after": "2026-08-17"
  },
  "mechanisms": [
    {
      "id": "coord-sync",
      "script": "adapters/claude-code/scripts/coord-sync.sh",
      "installer": "adapters/claude-code/scripts/install-coord-sync-task.ps1",
      "managed_by": "nl-maintenance",
      "declared_cadence_seconds": 60,
      "measured_cycle_seconds": 110,
      "measured_source": "<citation>",
      "calibration_status": "measured",
      "platform_cost_lines": { "windows": { "spawn_cost_ms": 152, "spawns_per_cycle": null } }
    }
  ]
}
```

`harness-doctor.sh`'s `check_schedule_manifest_cadence` WARNs when `declared_cadence_seconds <
ratio_floor * measured_cycle_seconds` for any entry that HAS a `measured_cycle_seconds`. Entries
with `measured_cycle_seconds: null` are calibration-pending and are silently skipped — an absent
measurement is not itself a violation; Stage 1 (`nl-maintenance.sh`) is where completion-anchored
scheduling makes the invariant true BY CONSTRUCTION and this manifest becomes that core's real job
table instead of a hand-maintained snapshot.

**Mechanized flip (HR-F7, 2026-08-03 harness review, gated-pipeline T7/REQ-A5):** "WARN for a
calibration week, then RED" used to be prose-only, with no stored date and no mechanism that ever
flipped it — the exact class constitution paragraph-1 bans. `cadence_check.warn_since`/`.red_after`
(and the matching pair on the new top-level `budget_check`, governing
`check_budget_bash_hooks`) fix that: the doctor stays WARN until `red_after`, then flips to RED on
its own, no operator action required. An entry whose `managed_by` is `"nl-maintenance"` is exempt
from the clock entirely once `state/nl-maintenance/activation-marker` exists — its own
completion-anchored scheduling already IS the WARN's prescribed remedy, so the doctor annotates it
`[doctor] NOTE ...satisfied-by-construction` instead of continuing to warn on a since-fixed
violation (the exact false positive HR-F7 proved: the pre-fix check never read `managed_by`, so
the remedy it prescribed never actually cleared the WARN).

**Real, live signal, not just a fixture**: this manifest's own `coord-sync` entry (declared 60s,
measured 110s) already WARNs on a real machine today — that's the actual C2 pathology from the
2026-08-02 RCA, now doctor-visible instead of merely documented in a comment.

## Per-Bash hook-count budget

`harness-doctor.sh`'s `check_budget_bash_hooks` counts total hook entries across every
`PreToolUse` matcher block whose `matcher` string contains `"Bash"` (covers both the bare
`"Bash"` matcher and the combined `"Bash|PowerShell"` matcher), checked against both the live
`settings.json` and the committed template. WARNs above 6 (the R3.3 target); the real reduction is
Stage 2's per-category stub work, not this check. Today's real count (~25) WARNs on every machine
— visibility first, enforcement later, matching invariant 2's own calibration-week posture. Same
mechanized flip as the cadence check above: `schedule-manifest.json`'s top-level `budget_check.
red_after` (HR-F7) is the stored date this WARN flips to RED at — no longer prose-only.

## SessionStart matcher narrowing

`settings.json.template`'s previously-single blank-matcher (`""`) `SessionStart` block matched
every source (`startup`, `resume`, `clear`) and carried BOTH the two heaviest hooks
(`harness-doctor.sh --quick`, `session-start-digest.sh`) and five lighter ones
(`session-start-auto-install.sh`, the automation-mode/account-switcher block,
`gh-account-blindness-hint.sh`, `broadcast-active-session.sh`, `workstreams-emit.sh
--on-session-start`). Task 1 splits it: the two heavy hooks move to a NEW `"startup|clear"`
matcher block (so a `resume` source never dispatches them at all — the direct fix for
`**Prove it works:** 1`); the five lighter hooks stay on the unchanged `""` block (they are
either already unconditionally single-flighted at the script level — `session-start-auto-
install.sh` — or cheap/idempotent enough that firing on resume too is the correct, intended
behavior, e.g. session-presence tracking).

`session-start-auto-install.sh` was NOT moved: it already uses `ss_singleflight`
unconditionally (no `NL_SESSIONSTART_ORIGIN` gate at all), so it was never part of the
resume-bypass class this task fixes.

### Known gap: the live reconcile (Edge Case 5)

`session-start-auto-install.sh`'s `merge_settings` is a per-COMMAND-STRING, ADDITIVE-ONLY sync:
it appends a template hook entry to the live `settings.json` only if none of that entry's
command strings already appear anywhere under the same event. Because this task's matcher
narrowing keeps the exact same two command strings (`NL_SESSIONSTART_ORIGIN=1 bash
~/.claude/hooks/harness-doctor.sh --quick` / `...session-start-digest.sh`) — just moved to a
different matcher block — `merge_settings` sees them as "already present" and does **nothing**:
it neither adds the new `"startup|clear"` block nor removes the old `""` block's copies. A
real machine's live `~/.claude/settings.json` therefore keeps dispatching doctor/digest on
EVERY SessionStart source (including resume) until a MANUAL reconcile — delete the two
`session-start-digest.sh`/`harness-doctor.sh --quick` lines from the live `""` block, confirm
they appear under the live `"startup|clear"` block instead — is run on that machine. This is
the exact, accepted, documented gap Edge Case 5 names; Stage 2 is where a doctor edge-profile
check (comparing live wiring against the template) makes this mechanically enforced instead of
manually verified. Task 1 ships the template fix and this runbook note; it does not mutate any
machine's live settings.json (worktree-isolated builds should never touch machine-wide state
outside the repo).
