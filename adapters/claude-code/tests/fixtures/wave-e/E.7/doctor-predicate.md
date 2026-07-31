# doctor predicate — E.7 session-resumer watchdog

For `harness-doctor.sh` (E.10 implements verbatim, per specs-e §E.0.1 /
§E.10.12 — this builder does not edit `harness-doctor.sh`).

## What this predicate verifies

Two independent facts, both required for a GREEN verdict on this unit:

1. The script exists, is executable, and declares a self-test entrypoint
   (mirrors every other manifest `selftest: true` unit's coverage check —
   `check_selftest_sweep` already sweeps any `hooks/*.sh` with
   `--self-test`, but `session-resumer.sh` lives under `scripts/`, not
   `hooks/`, so it needs its own predicate rather than falling under that
   existing sweep).
2. The Windows Scheduled Task `NL-session-resumer` is registered on the
   live machine (a fact this task's own builder cannot make true — task
   registration is an orchestrator/operator step per specs-e §E.W.6).

## Exact command + RED condition

```bash
# --- Check A: script presence + self-test entrypoint (any platform) ---
SCRIPT="${live_home}/scripts/session-resumer.sh"
if [[ ! -f "$SCRIPT" ]] || [[ ! -x "$SCRIPT" ]]; then
  RED "session-resumer" "session-resumer.sh missing or not executable at ${SCRIPT}"
elif ! grep -q -- '--self-test' "$SCRIPT"; then
  RED "session-resumer" "session-resumer.sh has no --self-test entrypoint"
fi

# --- Check B: scheduled-task registration (Windows only; --full mode) ---
# MSYS_NO_PATHCONV=1 is REQUIRED under Git Bash — without it, MSYS mangles
# the leading-slash /Query and /TN flags into Windows path fragments and
# schtasks fails with an argument-parsing error unrelated to task
# existence (verified empirically 2026-07-03: `schtasks /Query /TN X`
# under plain Git Bash raises "Invalid argument/option - 'C:/.../Query'";
# `MSYS_NO_PATHCONV=1 schtasks /Query /TN X` on a MISSING task correctly
# exits 1 with "ERROR: The system cannot find the file specified.", and
# on an EXISTING task exits 0 with a TaskName/Status table on stdout).
if command -v schtasks >/dev/null 2>&1; then
  if MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer" >/dev/null 2>&1; then
    # GREEN — task registered; no line emitted (doctor convention: silence = pass)
    :
  else
    WARN "session-resumer" "scheduled task 'NL-session-resumer' not registered — documented (see session-resumer.sh header for the exact schtasks /Create line), not registered. Not yet RED: registration is an orchestrator/operator step (specs-e §E.W.6), so a fresh clone or a not-yet-cut-over machine is an HONEST warn, not a doctor failure, until the orchestrator runs §E.W step 6."
  fi
else
  # non-Windows dev machine (unlikely for this harness, but never crash):
  WARN "session-resumer" "schtasks not available on this platform — scheduled-task check skipped"
fi
```

## Why WARN, not RED, for Check B

Per the same pattern the manifest schema already uses for `honest_status`
(a gate that legitimately fires somewhere other than the template gets a
named honest status, not a RED): a fresh checkout of this repo, or any
machine before the orchestrator's §E.W step 6 runs, will correctly show
"not registered." This is honest-status territory, not a defect — RED-ing
it would make the doctor lie about what THIS BUILD's job was (build the
script + fixtures + self-test; registration is explicitly out of scope
per specs-e §E.0.1/§E.7). The moment E.10 wires this predicate AND the
orchestrator has run §E.W.6 on the reference machine, the WARN clears
itself (exit 0, task exists) with no further code change.

## Fixture for a red/warn self-test scenario

`harness-doctor.sh --self-test` (E.10's fixture suite) should include:

- **WARN fixture**: `HARNESS_SELFTEST=1` sandbox where `scripts/` contains
  a stub `session-resumer.sh` (executable, has `--self-test` grep-hit) and
  `schtasks /Query /TN "NL-session-resumer"` is stubbed/mocked to exit 1
  (task absent) — asserts the WARN line fires with the exact wording
  above, and the overall self-test suite still exits 0 (WARN never fails
  the suite, only RED does, per the doctor's existing WARN/RED contract
  in `_warn`/`_red`).
- **RED fixture**: same sandbox but the stub script is missing the
  `--self-test` string (or the file is deleted / non-executable) —
  asserts Check A's RED line fires with the missing-or-not-executable
  detail.
- **GREEN fixture**: stub script present + executable + has `--self-test`,
  AND the schtasks stub exits 0 — asserts zero RED/WARN lines for this
  unit.

## Digest feed path (for E.1's session-start-digest.sh, cross-reference)

Not a doctor predicate, but recorded here since E.1 needs to know where to
read: `session-resumer.sh` appends one JSON line per action to
`~/.claude/state/resumer/digest-feed.jsonl`
(`{"ts","session_id","event","detail"}`, event one of `classify-skip |
resume-attempt | resume-unresumable | resume-fallback | backoff-wait |
escalation | storm-cap-queued | would-have-resumed | tombstone`). E.1's
digest should render a single feed line: count of `resume-attempt`/
`resume-fallback` events in the last 24h + the most recent one's `detail`,
tolerating the file's total absence (a quiet harness with nothing to resume
never creates it).

## Activation guardrails (E.7 activation preconditions, operator concern
2026-07-06 — nl-issue ledger entry "E.7 ACTIVATION PRECONDITIONS")

Before the orchestrator runs §E.W step 6 to register the scheduled task, it
MUST register it in SHADOW MODE first (`RESUMER_SHADOW=1` in the `/TR`
command — see `docs/runbooks/session-resumer.md`), observe >=2 days of
`would-have-resumed` digest lines, and only then re-register without the
env var to arm it. This is a rollout-process precondition, not a new doctor
predicate: Check B above still only verifies the task is REGISTERED (it
cannot distinguish shadow-registered from armed-registered from the task
name alone, since `RESUMER_SHADOW` is baked into the `/TR` command string,
not queryable via `schtasks /Query`'s summary output). An operator wanting
to confirm shadow-vs-armed reads the task's actual `/TR` string:

```bash
MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer" /V /FO LIST | grep -i "Task To Run"
```

Kill switch (documented fully in the runbook): `schtasks /Change /TN
"NL-session-resumer" /DISABLE`. Tombstone verb: `session-resumer.sh --never
<session-id>` (writes `~/.claude/state/resumer/never/<session-id>` — path
corrected per ADR-061 §2; earlier docs said `state/session-resumer/never/`
while the code always used `state/resumer/never/`).
Storm-cap tuning: `RESUMER_STORM_CAP` env var (default 2/hour, 0=uncapped).
