# Session-end protocol — compact
> Enforcement: `continuation-enforcer.sh` (Stop hook, blocks without a valid marker)
> Applies: the last line of every turn

Every turn ends with exactly one marker, alone on the last non-empty line:

- **`DONE: <what shipped>`** — every declared task complete, no incomplete
  TodoWrite items, summary cites SHAs/artifacts. Never DONE while a verification
  gate is blocking — that is a lie by construction.
- **`PAUSING: <reason + exact ask>`** — genuinely hard-to-reverse decision only
  (constitution §8). The exact ask: what you need, why it's theirs, what you do
  the moment they answer. "Waiting for your input" is invalid — name the specific
  question and the concrete unblock.
- **`BLOCKED: <specific blocker + what unblocks it>`** — missing credential,
  external dependency, environment gap. Name what's needed with enough detail a
  future session can pick it up cold.
- **`CONTINUING: <verified-running work + wake mechanism>`** — background work is
  genuinely still executing; you verified it, not assumed it.

Two markers, a keyword-only marker, or an empty summary all fail. `DONE` while a
`TodoWrite` item is incomplete fails.

**Never out-wait a gate.** If `pre-stop-verifier` or an acceptance gate blocks
you, the work is not done — riding a retry-guard downgrade or claiming DONE past
a block is dishonest. Fix the work, or end with `PAUSING`/`BLOCKED` naming the
gap.

Keep-going (constitution §8) kills PERMISSION stops ("shall I continue?") —
never VERIFICATION stops. If there is more declared work and no genuine blocker,
there is no valid marker for "pause anyway" — keep working.

**Context pressure is never a valid `PAUSING`/`BLOCKED` reason** (added
2026-07-20 after a proven incident: a session read `context-watermark.sh`'s
percentage as authoritative capacity and PAUSED a multi-hour program,
abandoning 28 of 34 remaining items — the hook was in fact measuring against
a stale denominator, but even a CORRECTLY measured high watermark would not
have justified stopping). Compaction exists precisely to make context
exhaustion a non-event — `pre-compact-continuity.sh` (PreCompact hook) and
`docs/runbooks/pre-compaction-snapshots.md` already checkpoint state
automatically across a compaction. The correct response to a context
watermark nag, at any percentage, against any window, is: checkpoint state
to a durable file per constitution §5, and keep going. It is never grounds
for `PAUSING` (no decision is being asked of the operator) and never grounds
for `BLOCKED` (nothing external is missing) — see
`docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md`
for the full incident writeup.
