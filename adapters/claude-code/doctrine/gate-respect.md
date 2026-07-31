# Gate-respect — compact
> Enforcement: Pattern — self-applied (constitution §7 is the core rule)
> Applies: any time a gate, hook, or classifier blocks an action

When a gate blocks: **diagnose, fix, waiver — in that order.**

1. **Diagnose.** Read the gate's stderr first — it names the trigger and the
   remediation paths. If unclear, read the hook's source (a few minutes). Don't
   reach for a bypass because the gate "feels strict."
2. **Fix.** Apply the remediation the gate's own message names — update the
   plan's declared scope, write the missing test, add the missing field. The fix
   should make the action satisfy the gate's contract, not route around it.
3. **Waiver — last resort, explicit operator say-so only.** Bypass flags
   (`--no-verify`, `DISABLE` envs, override markers) require the operator's
   explicit authorization **in the current conversation** — not inferred, not a
   standing prior permission, not a previous session's approval. Use only when
   you can state in one sentence, with concrete evidence, why the gate is a
   false positive for THIS case. Log the bypass in the commit or session
   summary.

Asking for bypass authorization is itself a signal to pause and re-read the
gate's message — many bypass requests dissolve on a second look.

**A gate that false-fires repeatedly is a bug, not friction.** File it as a
harness gap with 2-3 concrete recurring examples and a proposed fix — don't
keep bypassing per-occurrence.

Never disable a gate by editing its source mid-session to make a block go away;
surface it instead.
