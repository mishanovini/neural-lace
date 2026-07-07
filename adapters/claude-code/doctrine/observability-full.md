# Observability (`nl`) — full

Full protocol for the NL Observability Program's derivation layer
(`hooks/lib/observability-derive.sh`, contract C4) and CLI
(`scripts/nl.sh`, contract C5). Compact summary: doctrine/observability.md.
Normative design: `docs/reviews/2026-07-04-observability-design-sketch.md`
(the two laws, the six operator questions, three surfaces, non-goals,
pre-registered success metrics — where this doc and the sketch conflict,
the sketch wins). Mechanical spec: `docs/plans/nl-observability-program-2026-08-specs-o.md` §O.0.3 (contracts), §O.3 (this task).

## The two laws

1. **DERIVE-DON'T-MAINTAIN.** Every "is this true right now" answer is
   computed from ground truth on read (heartbeats, the signal ledger, the
   NEEDS-YOU ledger, transcripts, docs/backlog.md) — never cooperatively
   maintained in a side file that can drift from reality. The one
   documented escape hatch (§O.4's divergence reconciler) exists ONLY while
   a legacy tree-state consumer is being retired, and it renders a visible
   drift badge rather than silently trusting the stale side-state.
2. **EVERY-SIGNAL-HAS-A-CONSUMER.** Every event type the signal ledger can
   receive has >=1 real reader, recorded in
   `adapters/claude-code/observability-consumer-map.json` (contract C3).
   `check_obs_consumer_map` (O.6, doctor-enforced) is the invariant's
   machine check.

## CANONICAL-COUNTERS-01 (full statement)

Never report an estate count (sessions, backlog rows, needs-you items,
harness-health gate counts, shipped commits, token costs) from an ad-hoc
`grep`/`jq` query when a canonical oracle already computes it — a second
implementation of the same count is exactly the class of bug this rule
exists to prevent (two "how many are stale" answers quietly disagreeing
because one was updated and the other wasn't). When no canonical oracle
exists yet for some count, name the ad-hoc definition you used inline so a
future canonicalization pass can find and replace it. Every `nl` output
line that reports a count carries `(oracle: <definition-id>)` — the
definition-ids in use: `od_sessions`, `od_needs_me`, `od_shipped_since`,
`od_harness_health`, `od_costs`, `od_backlog_health`, `od_why`.

## `nl` subcommands — full contract

All defined in `scripts/nl.sh` (C5), each a thin dispatcher over the
matching `hooks/lib/observability-derive.sh` (C4) function. Every
subcommand accepts `--json` for machine-readable output; JSON payloads
always carry `"schema":1` and `"oracle":"<function-name>"` at the top
level.

- **`nl status`** (Q1 + Q4 header) — one doctor-verdict header line
  (`od_harness_health`'s cached verdict), then the session board
  (`od_sessions`). `nl status --json` composes `{sessions, doctor}` and
  deliberately does NOT carry `od_harness_health`'s `.gates[]` array (the
  Q1 board is this subcommand's job) — see `nl health` below for the full
  Q4 answer. Session states, EACH with a written ground-truth
  derivation rule (advocate plan-time review 2026-07-06 — specs-o §O.0.3
  contract C4, binding; builders/consumers never invent a rule):
  - `waiting-on-me` — a NEEDS-YOU OPEN ledger entry names this
    session_id (joined via `needs-you.sh has-entry-for-session`).
  - `crashed` — C1 heartbeat stale AND recorded pid not alive.
  - `stalled` — C1 heartbeat stale AND recorded pid alive (chip detail
    carries "pid alive").
  - `throttled` — the session's most recent ledger
    `gate=resumer event=throttle-detected` timestamp is NEWER than its
    last activity timestamp (heartbeat `last_activity_ts`, else
    transcript mtime).
  - `blocked` — the session's newest ledger `block` event timestamp is
    NEWER than its last transcript activity (mtime) — a block it has
    not yet responded past.
  - `unobserved-cloud` — session_id appears in ledger lifecycle/spawn
    events (`session-start`/`session-stop`/`spawn-dispatched`/
    `spawn-concluded`) or a remote ledger
    (`~/.claude/state/remote-ledgers/*.jsonl`), but has NO local
    heartbeat file AND no local transcript file — an honest "can't
    observe this one from here" report, never fabricated.
  - `working` — fresh heartbeat (live), none of the above hold.

  **Priority on ties** (a session can satisfy more than one rule at
  once): `waiting-on-me` > `crashed` > `stalled` > `throttled` >
  `blocked` > `working`.
- **`nl needs-me`** (Q2) — every OPEN item in
  `~/.claude/state/needs-you/ledger.json` (via `needs-you.sh`'s own
  reader — THE oracle; never re-derived from the rendered
  `NEEDS-YOU.md`, which is a display artifact, not ground truth).
- **`nl why <session> [--last-block]`** (Q6) — merges signal-ledger
  lines for that session_id (time-ordered, every gate) into a causal
  chain, one line per step: `ts  gate  event  detail`. Ends with a
  one-line verdict: what blocked, what state it read, what the session
  did next. `--json` mode carries this SAME verdict text as a top-level
  `"verdict"` string field (verifier-round fix: the JSON payload used to
  omit it entirely — the printf building it sat after the json_mode
  early-return — so a JSON consumer never saw a verdict at all even
  though text mode always had one; the verdict is now computed once,
  ahead of the json_mode branch, and both output modes read the same
  value). `--last-block` narrows to the newest `block` event +/- 2
  lines of surrounding context, capped so the drill's <=20-output-line
  bar is always achievable. This is the sketch's "024 diagnosis in
  ~2 min" turned into a mechanical oracle: given a spawn-writer/gate
  race session id, `nl why <sid> --last-block` names the writer
  (`spawn-dispatched`), the blocking gate (`block` event), the retry,
  and the eventual allow — in one command instead of a manual ledger
  archaeology session.
- **`nl costs [<session>]`** (Q5) — sums transcript JSONL `usage`
  blocks (`input_tokens`, `output_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`) via a
  TAIL-FIRST read: bounded tail window (default 5000 lines,
  `OBS_COSTS_TAIL_LINES` override) for a NAMED session; tolerant of a
  partial/rotated transcript — if the tail window's first line is not
  independently parseable JSON (a mid-file cut, not a missing brace —
  truncation happens at the END of a line, so a naive "does it start
  with `{`" check does NOT catch this; the correct check parses the
  line alone and drops it on failure), it is dropped and the section is
  labeled `partial-tail-truncated-first-line-skipped` rather than
  erroring or
  silently under-counting the rest of the file. Also reports throttle
  events + an estimated `throttle_count * 5` minutes lost, joined from
  `gate=resumer event=throttle-detected` ledger lines (session-resumer.sh
  already normalizes several raw classifications into this one event
  name; the ledger `detail` field carries the original classification
  as `orig_event=...`). WITHOUT a named session (the aggregate-all-
  sessions form), a large multi-project machine can have hundreds of
  transcript files, some many MB each — livesmoke measured a full
  unbounded scan at 20+ seconds against a real 554-transcript estate
  (>10s bar) — so the no-session form scans only the
  `OBS_COSTS_MAX_TRANSCRIPTS` (default 10) most-recently-modified
  transcripts at a reduced `OBS_COSTS_AGGREGATE_TAIL_LINES` (default
  500, vs the single-session default 5000) per-file depth, and says so
  honestly via a `truncated_to_recent`/text note rather than silently
  costing a smaller universe unlabeled. Set `OBS_COSTS_MAX_TRANSCRIPTS=0`
  for a full untruncated scan (slow; not the default for a reason).
- **`nl shipped [--since <ts>]`** (Q3) — `git log --since <ts>` on the
  repo's shipped branch (defaults to `master`; falls back to `HEAD` if
  no branch literally named `master` exists — relevant for fixture
  repos, not the real checkout) for shipped SHAs + subjects; `docs/decisions/`
  files added in-window (`git log --diff-filter=A --name-only`); ledger
  `block`/`downgrade` events in the same window as a failures count. No
  existing helper computed any of this before O.3 — built fresh (there
  is no plan-COMPLETED-transition scan yet; a future task could add one
  by grepping `docs/plans/*.md` diffs for an added `Status: COMPLETED`
  line in the same window).
- **`nl backlog`** — `od_backlog_health`, mirroring
  `harness-kpis.sh`'s `_kpi_backlog_section` byte-for-byte (position-
  anchored terminal-marker detection, R1-R4 rules; per-priority open-row
  counts; age-tier histogram at the SAME 0-7/8-30/31-90/>90-day
  boundaries the KPI report uses — the specs-o high/medium/low priority
  THRESHOLDS (7/30/90 days) are a *different* axis from this fixed
  histogram bucketing and both are reported). Disposition words for an
  overdue row: `SCHEDULE` (spawn a task) / `FOLD` (name an absorbing
  plan) / `DEMOTE` (lower its priority tier) / `WONTFIX` (state a
  reason) — same vocabulary `session-start-digest.sh`'s
  `feed_backlog_accountability` nag line already uses. O.9 owns
  re-pointing the three existing BACKLOG-LOOP-01 consumers
  (`session-start-digest.sh:feed_backlog_accountability`,
  `harness-kpis.sh:_kpi_backlog_section`,
  `plan-edit-validator.sh:check_backlog_absorption_warn` — each
  currently an independently-maintained copy of the same
  `_backlog_row_is_terminal` regex) at this function; until that
  re-point lands, `od_backlog_health` is a byte-faithful mirror of the
  richest existing copy, not yet the single implementation those three
  call.
- **`nl health`** (Q4, full) — direct passthrough to `od_harness_health`:
  the cached doctor verdict PLUS the full per-gate 7-day
  block/waiver/downgrade breakdown (`.gates[]`, each entry
  `{gate,block_7d,waiver_7d,downgrade_7d,dominant}`) with a
  `[waiver-dominant]` flag in text mode when a gate's waiver count
  exceeds both its block and downgrade counts. `nl status`'s header line
  stays a one-line summary (verdict + cache timestamp only) by design —
  `nl health` is the subcommand that answers Q4 in full without a
  consumer having to re-derive the per-gate breakdown itself.

## Read-only; zero state writes

Every `od_*` function only reads. None of them create, mutate, or delete
any file — the library is safe to call from a CLI, a doctor predicate
(O.6), or a cockpit refresh loop (O.4) concurrently, with no write-locking
concerns, because there is nothing to lock.

## Cross-machine (read-both, no sync)

`od_sessions` also reads `~/.claude/state/remote-ledgers/*.jsonl` when
present (a per-machine drop location for another machine's ledger export)
and lists any session_id found there but not among local heartbeats AND
not among local transcripts as `unobserved-cloud`. No synchronization
mechanism is built — this is a read-both, not a merge; out of scope per
the sketch.

## Sandboxing knobs (env-var overrides, all self-test-only)

`HEARTBEAT_STATE_DIR`, `SIGNAL_LEDGER_PATH`, `NEEDS_YOU_STATE_DIR`, plus
the advocate-review 2026-07-06 amendment set (specs-o §O.0.1-3 — every C4
ground-truth input redirectable): `OBS_TRANSCRIPTS_ROOT` (transcripts dir;
od_costs/od_why/od_sessions), `OBS_MAIN_CHECKOUT` (git root;
od_shipped_since), `OBS_DOCTOR_CACHE_DIR` (doctor-cache.json's directory;
od_harness_health — falls back to the digest's own `DOCTOR_CACHE_PATH`
exact-file override, then production default), `OBS_BACKLOG_PATH`
(docs/backlog.md; od_backlog_health). Plus `OBS_REMOTE_LEDGERS_DIR`,
`OBS_STALE_MIN` (heartbeat staleness minutes, default 30),
`OBS_HEALTH_WINDOW_DAYS` (harness-health lookback, default 7),
`OBS_COSTS_TAIL_LINES` (single-session transcript tail window, default
5000), `OBS_COSTS_AGGREGATE_TAIL_LINES` (per-file tail window for the
no-session aggregate `nl costs` scan, default 500),
`OBS_COSTS_MAX_TRANSCRIPTS` (cap on how many most-recently-modified
transcripts the aggregate scan costs, default 10; `0` = unbounded),
`OBS_SHIPPED_BRANCH` (branch `od_shipped_since` reads, default `master`
falling back to `HEAD`). None of these are read by anything outside
`hooks/lib/observability-derive.sh` and `scripts/nl.sh`; production
invocations never set them.
