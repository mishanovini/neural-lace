# Task 8 Evidence — SessionStart fallback-queue drainer

Plan: `docs/plans/decision-context-gate-2026-05-29.md`
Task 8: author the SessionStart fallback-queue drainer + self-test + mirror.

## Artifact

- `adapters/claude-code/hooks/decision-context-replay.sh` (new)
- `~/.claude/hooks/decision-context-replay.sh` (mirror, byte-identical)

## Self-test

```
$ bash adapters/claude-code/hooks/decision-context-replay.sh --self-test
... 24 assertions ...
self-test: 24 pass, 0 fail
self-test: OK 24/24
```

Scenarios exercised: ST1 (no file), ST2 (empty file), ST3 (3 events facade-up),
ST4 (3 events facade-down), ST5 (mixed wrapped + raw), ST6 (cap with
DC_REPLAY_MAX_DRAIN=5 against 12 entries — oldest 7 deferred, newest 5
drained), ST7 (idempotency: re-fire same event, facade dedupes), ST8
(malformed JSON lines skipped without crash).

## Task 8 — Comprehension Articulation (builder-authored)

### Spec meaning

Task 8 ships a SessionStart hook that DRAINS the Decision-Context fallback
queue at `~/.claude/state/decision-context/fallback.jsonl`. The queue is
populated by two upstream writers:

1. `decision-context-gate.sh` (Task 4 — Stop hook) writes RAW event JSON,
   one event per line, when the state.js facade is unreachable on its emit
   path (lines 276-289 of the gate's `_emit_dual_with_fallback`).
2. `decision-context-reply-emit.sh` (Task 6 — UserPromptSubmit writer)
   writes WRAPPED entries `{"sink":<path>,"event":{...},"queued_at":<iso>}`
   via its `_fallback_write` helper (line 139-150 of the reply-emit hook).

The drainer must handle BOTH formats, re-emit each event via the state.js
facade `appendEvent(eventInput, { statePath: sink })`, rewrite the queue
file atomically with only the undrained lines, and never block session
boot (SessionStart hooks always exit 0). Idempotency is delegated to the
facade — every event carries a deterministic `event_id`; re-emit is a
per-file no-op per ADR-032 §2.

### Edge cases covered

- **No fallback file** (ST1): silent no-op exit 0; sink not touched.
- **Empty fallback file** (ST2): delete the file (clean state) and exit
  silently; behavior locked at lines 250-255 of the script.
- **Facade-up, all events drained** (ST3): file is deleted at end of
  successful full drain via `fs.unlinkSync(fbFile)` (line 217 of the
  embedded node program).
- **Facade-down (broken state-lib path)** (ST4): zero events drained, file
  contents preserved byte-identical; the outer `_drain_all` returns
  `0|0|0` via the `LIBERR:*` case at line 256-258 of the bash side.
- **Mixed wrapped + raw events in same queue** (ST5): detection by checking
  if `parsed.event` is an object — if yes, unwrap to (parsed.sink,
  parsed.event); else treat as raw and emit to the default resolved sink
  (lines 153-162 of the embedded node program).
- **Cap (>1000 entries)** (ST6): drain only the NEWEST MAX_DRAIN entries
  (slice from `lines.length - maxDrain`), defer oldest by prepending them
  back onto the rewritten file. Cap is overridable via env var
  `DC_REPLAY_MAX_DRAIN` for the self-test. Cap warning written to stderr
  (lines 137-143 of the embedded node program).
- **Idempotency (re-fire same event after partial drain)** (ST7): facade
  dedupes by `event_id` so the second emit is a per-file no-op; the line
  is still counted as drained and the queue file is removed.
- **Malformed JSON line in queue** (ST8): caught by try/catch around
  `JSON.parse(line)`; logged to stderr as a warning, line counted as
  "malformed" and SKIPPED (not retained — see "Edge cases NOT covered"
  for the design rationale); loop continues with the next line.
- **Mid-drain facade outage** (FACADE_DOWN_MID_DRAIN): when `appendEvent`
  throws after several events successfully drained, the loop sets
  `stopFurther = true` so all remaining lines (including the one that
  just failed) are written back to the queue intact. This avoids
  re-trying against a known-down facade and produces accurate "drained
  N, deferred M" counts.
- **Sentinel records** (FACADE_DOWN_SENTINEL): the reply-emit hook can
  emit `{"type":"_facade_down_sentinel",...}` audit markers; the drainer
  detects these and counts them as drained (line removed) without
  attempting a facade emit (lines 164-169 of the embedded node program).
- **Non-event line shape** (e.g. JSON that parses but has no `.type`):
  classified as malformed and skipped (lines 172-176 of the embedded
  node program).

### Edge cases NOT covered

- **Cross-session simultaneous SessionStart drainers.** If two sessions
  start at the same instant on the same machine, both could read the
  same fallback file, both attempt drain, and the second's atomic
  rewrite would clobber the first's. Mitigation in practice: SessionStart
  is rarely concurrent within milliseconds; facade dedupe makes
  double-emit harmless even if the queue rewrite races. Out-of-scope
  per Task 8 spec — no flock requested.
- **Malformed lines are dropped, not quarantined.** A malformed line is
  silently logged + skipped; it does not move to a sidecar
  "fallback-malformed.jsonl". Rationale: the upstream writers produce
  JSON via `JSON.stringify`, so malformed lines almost certainly
  indicate file corruption (partial write, disk full) — not legitimate
  data we want to preserve. The log warning is the audit trail. If
  malformed-line preservation becomes important, a sidecar file is a
  Tier-1 follow-up.
- **Per-event retries.** When `appendEvent` throws mid-drain, the
  drainer STOPS rather than retrying or skipping the bad event. This is
  the spec-stated behavior ("don't keep retrying — defer to next
  session"). A future enhancement could distinguish transient (retry
  next session) from permanent (move to dead-letter) failures.
- **Queue-file lock against concurrent writers.** Both upstream writers
  use `appendFileSync` which is atomic per-line on POSIX but not
  guaranteed atomic on Windows. The drainer could in theory clobber a
  write in flight from the gate or reply-emit. Mitigation: the
  rewrite-temp-then-rename uses a PID suffix so collisions are unlikely
  in practice. Out-of-scope per Task 8 spec.
- **Sink directory creation race.** The embedded node program calls
  `fs.mkdirSync(path.dirname(sinkPath), { recursive: true })` before
  every emit; concurrent drainers/writers calling this simultaneously
  could in theory hit EEXIST race conditions but `recursive: true`
  handles that. Considered covered.

### Assumptions

- The state.js facade's `appendEvent(eventInput, { statePath: sink })`
  is the canonical write path. Both upstream writers use it; the
  drainer reuses it. Verified by reading
  `neural-lace/conversation-tree-ui/state/state.js` lines 46-48 (the
  facade method) and lines 87+ (the exports table).
- The facade's per-file idempotency-on-event_id is unconditional —
  re-emitting an event with an already-seen `event_id` to the same
  `statePath` is a no-op. Verified by ADR-032 §2 + the gate's
  defensive `branch-opened` pattern at gate line 461-470 ("Idempotent
  on event_id per ADR-032 sec.2 -- if --on-session-start already
  emitted this same node, the facade dedupes silently").
- Wrapped lines `{"sink":<path>,"event":<event>,...}` always have a
  string `sink` value. Verified by reading reply-emit's `_fallback_write`
  at lines 139-150 — the only writer of that shape. If `sink` is empty
  string or missing, we fall back to the default resolved sink (line
  155 of the embedded node program).
- The default resolved sink is the GUI's `tree-state.json` (resolved
  via `_resolve_gui_state_path`), mirroring the conversation-tree-emit
  resolver pattern. Raw events without a wrapper land here; the gate's
  raw-event emits originally targeted this sink (or the gate-state
  path) on the live emit attempt, so re-emitting to the GUI sink is
  the closest fidelity-preserving recovery.
- Cap order: newest-first drain (oldest-deferred) minimizes
  user-observable staleness in the GUI. The latest decisions surface
  immediately; oldest deferred entries trickle out over subsequent
  SessionStart runs (each new run picks up the previous run's
  deferred-head as the queue grows shorter). This was my design call
  per spec ("pick an order that minimizes user-observable staleness").
- SessionStart receives JSON on stdin per the Claude Code hook contract,
  but the payload is unused. Reading stdin to `/dev/null` prevents the
  hook from hanging if invoked from a pipe with no consumer.
- `node` and `jq` are available — both are required by every adjacent
  hook in this substrate (`decision-context-gate.sh`,
  `decision-context-reply-emit.sh`, `conversation-tree-emit.sh`). If
  `node` is unavailable, the drainer logs and exits 0; the queue
  persists until a session with `node` runs the drainer.
