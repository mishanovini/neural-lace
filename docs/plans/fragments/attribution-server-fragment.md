# Fragment: attribution-pipeline task — consumer contract for the cockpit's per-task "running" chip

Harness-side work (branch `wip/harness-hardening-2026-07-29`) landed the
NL-ATTRIBUTION header convention + parser (doctrine:
`doctrine/orchestrator-pattern.md` / `doctrine/orchestrator-pattern-full.md`)
so a dispatch prompt CAN now carry a machine-readable `plan=<slug>
task=<id> role=<...>` triple. This fragment is the consumer contract for
`neural-lace/workstreams-ui/server/roadmap-routes.js` — the file THIS task
does not edit directly (a different builder owns it) — describing exactly
how `deriveLiveAgentLeaves` (or a new joiner alongside it) should bind a
live dispatch to a `<plan>/<task>` node so the "N running, unattributed to
a task" banner stops being the default state.

## 0. What already works today, unconditionally improved by this change

`deriveTaskNode` already builds `sessionsByTask[task_id]` from
`task_started`/`task_done` progress-log events (`eventsForSlug` ->
`deriveLib.readAskEvents`), which `_emit_dispatch_provenance` in
`workstreams-emit.sh` already emits at `--on-builder-dispatch` time. That
pipe is UNCHANGED in shape — this task only made its INPUT more reliable:
the header, when present, is now AUTHORITATIVE for `--plan-slug`/`--task-id`
and bypasses the old free-text heuristic (`_extract_plan_slug`/
`_extract_task_id`, which only matched literal `docs/plans/X.md` +
`Task N of` phrasing). No `roadmap-routes.js` change is required for this
half — adopting the header in dispatch prompts alone raises the
`sessionsByTask` hit rate with zero server-side work. The rest of this
fragment is about the ADDITIONAL signals now available for a richer,
more-certain "is this actually still running" chip.

## 1. The two NEW event sources

### 1a. START — governor ledger (`~/.claude/state/governor/ledger/<host>.jsonl`)

Written by `hooks/lib/admission-lib.sh`'s `adm_admit` (sourced from
`workstreams-emit.sh`'s `--on-builder-dispatch`), ONE row per dispatch,
already the highest-volume event this harness produces (2033 rows on this
machine as of this fragment's build — see §4 for the honest adoption
number). Relevant fields for attribution (added by this task; everything
else pre-existed): `plan`, `task`, `role`, `attributed` — all STRING type
even where they read as numbers/booleans (`"attributed":"1"`, not `1`).
`attributed=="0"` rows omit `plan`/`task`/`role` entirely when the header
was fully absent (never a guessed empty string); a PARTIAL header (e.g.
`plan=` present, `task=` missing) still keeps `attributed:"0"` but DOES
carry the parsed `plan` value — the field's presence does not imply
`attributed=="1"`, always gate on `attributed` explicitly.

Real example rows (generated live against this build, not fabricated —
commands + full transcript in this task's build report):

```jsonc
// attributed=1 — full header present
{"wall":"2026-07-30T05:41:45Z","mono":"1785390105","mono_src":"wall","host":"Mishas-Mac-mini","source":"emit-feed","verdict":"admit","pressure":"unknown","pressure_src":"absent","live_sessions":-1,"rate_1m":1,"protected":0,"mode":"observe","kind":"fg","plan":"attribution-pipeline","task":"1","role":"builder","attributed":"1"}

// attributed=0 — no header at all (the pre-convention, still-most-common shape)
{"wall":"2026-07-30T05:42:44Z","mono":"1785390164","mono_src":"wall","host":"Mishas-Mac-mini","source":"emit-feed","verdict":"admit","pressure":"unknown","pressure_src":"absent","live_sessions":-1,"rate_1m":1,"protected":0,"mode":"observe","kind":"fg","attributed":"0"}
```

Note what is NOT in this row: the child's own future session_id. This row
is written by the DISPATCHING (parent/orchestrator) session's PreToolUse
hook, before the child session exists — there is no stable local hook
event for "child session N was created for dispatch X" (same ADR-054
ceiling `workstreams-emit.sh`'s own header documents for background-task
completion). Do not attempt to bind this row's session/host to a
heartbeat; use plan+task+recency instead (§2).

### 1b. END — signal ledger (`ledger_emit`'s configured path; see
`hooks/lib/signal-ledger.sh` — `SIGNAL_LEDGER_PATH` override or the
production default under `~/.claude/state/`)

Written by `workstreams-emit.sh`'s `--on-stop` (`_run_on_stop`), the SAME
`gate:"workstreams-emit"` `event:"spawn-concluded"` row that already
existed (Wave O, OBS2) — this task only enriched its `detail` string. The
signal-ledger schema itself is FROZEN at `{ts, session_id, gate, event,
detail}` (constitution-adjacent discipline: do not add top-level fields to
a shared writer's row shape), so plan/task/role/attributed live INSIDE
`detail` as `key=value` tokens, space-joined, parse with a simple
`key=(\S*)` regex per field — do not split on spaces naively since `detail`
also carries `session=`/`concluded=`/`shipped=` in the same string.

Real example row (generated live, same build):

```jsonc
{"ts":"2026-07-30T05:42:24Z","session_id":"<the STOPPING session's OWN outer wrapper id — see caveat below>","gate":"workstreams-emit","event":"spawn-concluded","detail":"session=sess-frag-child-a1b2c3 concluded=1 shipped=0 plan=attribution-pipeline task=1 role=builder attributed=1"}
```

CAVEAT (found while generating this fixture, worth carrying into the
reader): `ledger_emit`'s own TOP-LEVEL `session_id` field is populated from
the `CLAUDE_CODE_SESSION_ID` env var (signal-ledger.sh's own convention),
which in a real running session equals the actual session id — but the
`detail` string's embedded `session=` token is derived independently, via
`workstreams-emit.sh`'s own `_session_id()` (reads the hook's JSON
`.session_id`, the value that actually varies per test/dispatch). **Always
read the `session=` token INSIDE `detail`, never the row's top-level
`session_id` field**, for the id this fragment's join logic needs — the two
happen to coincide in a real single-session Claude Code process today, but
nothing about the signal-ledger contract guarantees it, and this task's own
fixture generation is proof they can diverge.

## 2. How to join: "started, not concluded, heartbeat-fresh" -> a live chip

For a given roadmap task `<slug>/<task_id>`:

1. Scan the governor ledger for `source=="emit-feed"`, `attributed=="1"`,
   `plan==<slug>`, `task==<task_id>` rows. Take the MOST RECENT by `wall`.
   If none exist, this task has never had an attributed dispatch — fall
   back to the pre-existing `sessionsByTask` (progress-log) pipe untouched
   (§0); this new signal is additive, not a replacement.
2. Scan the signal ledger for `gate=="workstreams-emit"`,
   `event=="spawn-concluded"` rows whose `detail` carries `plan=<slug>
   task=<task_id>` AT A LATER `ts` than the START row found in step 1. If
   found -> this dispatch has CONCLUDED; do not render a live chip from it
   (fall through to whatever `sessionsByTask`/heartbeat evidence says
   independently — a task can have a second, later, still-running
   dispatch).
3. If no matching END row exists after the START row: render the live
   chip, LABELED PROVISIONALLY (e.g. "dispatched, not yet confirmed
   running") until corroborated by a heartbeat-fresh session in
   `sessionsByTask[task_id]` (§0's existing pipe) — the START row alone
   proves a dispatch was ISSUED, not that a session is currently alive
   (the honest gap in §3). Do not upgrade to a plain "running" label on
   the START row alone.
4. A `spawn-concluded` row (step 2) with NO matching START row within a
   reasonable lookback window (recommend: the same window
   `DISPATCH_REPLAY_DEBOUNCE_SECONDS`-adjacent order of magnitude is too
   short; use something like 24h, this machine's realistic dispatch
   longest-run) is ITS OWN HONEST CLASS — "a session concluded that we
   never observed starting" — render it distinctly (e.g. in a diagnostics
   panel), never silently drop it and never mis-render it as a currently
   running task.

## 3. The honest gap this fragment does NOT close

The START row's implicit "session" is the DISPATCHING PARENT's session id;
the END row's `session=` token is the DISPATCHED CHILD's own id. These are
NECESSARILY different ids for any `Task`/`Agent`-tool dispatch (a
PreToolUse hook cannot know a not-yet-created child's session id — same
documented ceiling as `dispatch-provenance.sh`'s `worktree_path`
UNRESOLVED case). Do NOT attempt to join START-to-END via session id; join
on `plan`+`task`+recency as in §2. This is a real, load-bearing limitation,
not an oversight — closing it fully would require either (a) the
dispatching SDK surfacing the child's session id back to the parent's
PreToolUse hook (not available today), or (b) the child self-registering
its own attribution at its own SessionStart by re-reading its first-turn
transcript (deliberately NOT built by this task — SessionStart's timing
relative to first-turn transcript completeness was not something this
task could safely assume without live verification; Stop-time reading,
used here, is the only point the transcript is GUARANTEED complete).

## 4. Honest adoption number (measured against the REAL ledger, not a self-test)

`~/.claude/state/governor/ledger/Mishas-Mac-mini.jsonl` on this machine:
2033 total `source=="emit-feed"` rows as of this fragment's build; **0
carry any `plan` label** (`grep -c '"plan":' <file>` -> 0). This is
expected and correct, not a bug: `~/.claude/hooks/` on this machine is a
symlink to the MASTER checkout, not this task's worktree, so no real
production dispatch has run the header-aware code yet — today's 0% is the
honest starting point for the retirement-condition clock named in
`doctrine/orchestrator-pattern-full.md` (">95% sustained for one month").
Every dispatch this task itself made (via the Agent tool, no header) would
also have logged `attributed:"0"` had it gone through the real hook path —
this task's own dispatch is the canonical "transition case" the WARN
counter (harness-side) exists to surface.

## 5. Integration points to re-verify at merge

- `grep -c '"plan":' ~/.claude/state/governor/ledger/<host>.jsonl` rises
  above 0 once orchestrator prompts adopt the header — a cheap adoption
  smoke-test, not a full test suite.
- `bash adapters/claude-code/hooks/workstreams-emit.sh --self-test` ->
  `self-test: OK` except the pre-existing ST11 red (filed
  WORKSTREAMS-EMIT-ST11-RED-01, unrelated to this task) — run on BOTH
  `/bin/bash` and the Homebrew interpreter.
- Once `deriveLiveAgentLeaves`/`deriveTaskNode` grows the §2 joiner:
  `node neural-lace/workstreams-ui/web/cockpit.selftest.js` (or the
  equivalent live suite for whichever file lands the join) should gain a
  scenario asserting a `plan`+`task`-matched governor-ledger START row
  with no signal-ledger END row renders a live chip, and the same pair
  WITH a later END row does not.
