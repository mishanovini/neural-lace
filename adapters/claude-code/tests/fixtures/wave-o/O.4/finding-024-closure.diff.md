# Proposed NL-FINDING-024 closure diff (specs-o §O.4 deliverable 5)

Builder: build/wave-o-o4. This builder does NOT edit `docs/findings.md`
directly (§O.0.1-2: "editing docs/backlog.md rows" is forbidden; findings.md
edits are the same class of durable-ledger edit and are called out in the
task instructions as orchestrator-applied). Proposed diff below for the
orchestrator to apply verbatim (or amend) once the O.4 retirement fragments
(template-wiring.md, manifest-amendments.md) actually land.

## Current entry (docs/findings.md line 214, unchanged fields kept for diff clarity)

```
### NL-FINDING-024 — workstreams spawn writer→gate is a PreToolUse RACE: first spawn of a title can block spuriously (waiver-tax generator)
- **Severity:** warn
- **Scope:** canon
- **Source:** orchestrator session 2026-07-03 ~18:25Z — spawn_task "Launch NL overhaul Wave E (E.0–E.10)" BLOCKED by workstreams-state-gate ("verified snapshot has no live node naming this spawn's branch") despite the writer firing correctly in the same attempt
- **Location:** adapters/claude-code/hooks/workstreams-emit.sh (--on-spawn, PreToolUse entry 29) × workstreams-state-gate.sh (PreToolUse entry 30, same matcher); design comment in --on-spawn claims it "genuinely satisfies the gate that runs immediately after (the ADR-031 r7 intended design)"
- **Status:** open
- **Description:** [... unchanged, PROVEN forensics + HYPOTHESIZED mechanism as originally recorded ...]
```

## Proposed replacement (Status flip + closure note appended to Description)

```
### NL-FINDING-024 — workstreams spawn writer→gate is a PreToolUse RACE: first spawn of a title can block spuriously (waiver-tax generator)
- **Severity:** warn
- **Scope:** canon
- **Source:** orchestrator session 2026-07-03 ~18:25Z — spawn_task "Launch NL overhaul Wave E (E.0–E.10)" BLOCKED by workstreams-state-gate ("verified snapshot has no live node naming this spawn's branch") despite the writer firing correctly in the same attempt
- **Location:** adapters/claude-code/hooks/workstreams-emit.sh (--on-spawn, PreToolUse entry 29) × workstreams-state-gate.sh (PreToolUse entry 30, same matcher); design comment in --on-spawn claims it "genuinely satisfies the gate that runs immediately after (the ADR-031 r7 intended design)"
- **Status:** closed (root retired — NL Observability Program Wave O, task O.4, 2026-07-06/07)
- **Description:** [... unchanged original PROVEN/HYPOTHESIZED text ...]

  **CLOSURE NOTE (O.4, specs-o §O.4 deliverable 4/5):** the race's SECOND
  party — `workstreams-state-gate.sh`'s two PreToolUse entries — is retired
  at the template layer (see `adapters/claude-code/tests/fixtures/wave-o/
  O.4/template-wiring.md`, `manifest-amendments.md`) once the Workstreams
  cockpit (`workstreams-ui/`) stopped reading `tree-state.json` as truth —
  its ONLY protected consumer. The race cannot recur because the gate that
  raced against the writer no longer runs. This is root closure, not a
  race-condition fix within the gate: per decision D-O4 (specs-o §O.0.5),
  the class of bug (a PreToolUse gate reading state before its sibling
  writer's fs write lands) is eliminated by removing the gate rather than
  hardening it, since law 2 (EVERY-SIGNAL-HAS-A-CONSUMER) says an
  unconsumed protection is dead weight, not defense-in-depth.

  Demonstrated mechanically (not just asserted): `nl why <session>
  --last-block` (contract C4/C5, task O.3) reconstructs this EXACT
  historical failure shape from a seeded fixture — see
  `adapters/claude-code/tests/fixtures/wave-o/O.3/` for the 024-class
  ledger fixture and `hooks/lib/observability-derive.sh`'s od_why
  self-test scenario asserting the reconstructed chain names the writer,
  the gate, the block reason, and the retry-then-allow outcome in <=20
  output lines — i.e. the ~40-minute manual log-archaeology this finding's
  own Source line describes is now a <2-minute `nl why` query, AND the
  underlying gate that produced the block is gone. Both the mechanical
  diagnosis tool (O.3) and the root-cause retirement (O.4) ship in the same
  Wave.
```

## Verification the orchestrator should perform before applying

1. Confirm `template-wiring.md`'s two removals have actually landed in
   `settings.json.template` (both `workstreams-state-gate.sh` PreToolUse
   entries gone).
2. Confirm `manifest-amendments.md` Entry 1 landed (workstreams-spawn-gate
   `wired_template: false`, `blocking: false`).
3. Run `bash adapters/claude-code/scripts/nl.sh why fixture-024-sid
   --last-block` (session id per `adapters/claude-code/tests/fixtures/
   wave-o/O.3/024-ledger.jsonl`, seeded under a sandboxed
   `SIGNAL_LEDGER_PATH` pointed at that fixture file) against the O.3
   fixture and confirm the causal chain output before flipping Status to
   closed — do not flip on the fragment's say-so alone.
