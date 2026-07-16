# Runbook: ask-rooted workstreams (progress log + ask registry + ask-tree UI)

<!-- STUB — Task 1 walking skeleton. Finalized by Task 17 (schema section,
     drift taxonomy, symptom->fix table, auditor cadence tuning, archival
     convention, triage order). Plan:
     docs/plans/ask-rooted-workstreams-p1.md -->

**What it is.** Every progress event on an operator ask (a task-verifier
checkbox flip, a dispatch, a NEEDS-YOU append, a master merge, a plan
amendment, a plan completion) is emitted by a MECHANISM — never by model
memory — into a per-ask JSONL log the workstreams-ui landing page renders as
a chronological narrative. This closes the failure class the old
event-sourced tracker had (0 production decision-events ever recorded) by
making the WRITE side mechanical instead of cooperative.

## Event flow (the walking skeleton — one event, every layer)

```
task-verifier flips "- [ ] N." -> "- [x] N." in a docs/plans/<slug>.md
        |
        v  (PostToolUse Edit|Write, settings.json.template — verified wired)
adapters/claude-code/hooks/plan-lifecycle.sh
  emit_task_done_progress_log_events()  -- diffs pre/post checked-task-id
  sets, resolves the plan header's `ask-id:`, and (best-effort, never
  blocks) shells out to:
        |
        v
adapters/claude-code/scripts/progress-log.sh emit --type task_done ...
        |
        v
adapters/claude-code/hooks/lib/progress-log-lib.sh  pl_emit()
  builds the versioned JSON event, dedups by the per-event-type natural
  key, and appends ONE LF-terminated line to:
        |
        v
~/.claude/state/progress-logs/<ask-id>.jsonl   (machine-local; D1)
        |
        v  (server-side read, no shelling on the request path)
neural-lace/workstreams-ui/server/server.js   GET /api/asks
  reads ~/.claude/state/ask-registry.jsonl (hand-registered for now;
  Task 8 automates capture) + every ask's own progress-log file
        |
        v
neural-lace/workstreams-ui/web/asks.js   fetch('/api/asks')
  renders one card per ask, one narrative line per event
        |
        v
http://127.0.0.1:7733/  -- the operator sees "task N verified done"
```

## File locations (Task 1 scope)

| Thing | Path |
|---|---|
| Progress-log writer lib | `adapters/claude-code/hooks/lib/progress-log-lib.sh` (`pl_emit`, `pl_path_for`) |
| Progress-log CLI | `adapters/claude-code/scripts/progress-log.sh` (`emit`, `--self-test`) |
| Verifier-flip splice | `adapters/claude-code/hooks/plan-lifecycle.sh` (`emit_task_done_progress_log_events`) |
| Ask registry stub (Task 1) | `adapters/claude-code/scripts/ask-registry.sh` (`register`, `list`, `--self-test`) — Task 8 replaces this with the full contract |
| Per-ask event log | `~/.claude/state/progress-logs/<ask-id>.jsonl` (or `unlinked.jsonl` when a plan has no `ask-id:` header yet) |
| Ask registry file | `~/.claude/state/ask-registry.jsonl` |
| Server route | `neural-lace/workstreams-ui/server/server.js` `GET /api/asks` (`buildAsksPayload()`) |
| Landing card renderer | `neural-lace/workstreams-ui/web/asks.js` |

## Sandboxing (every self-test + manual walkthrough)

Both writer scripts resolve their state directory the same way (mirrors
`session-heartbeat.sh`/`needs-you.sh`):

1. An explicit env override (`PROGRESS_LOG_STATE_DIR`, `ASK_REGISTRY_STATE_DIR`).
2. `HARNESS_SELFTEST=1` with no override -> a sandboxed dir under
   `${TMPDIR:-/tmp}/<script-name>-selftest/<pid>/`.
3. Default: the real `$HOME/.claude/state/...` path.

The server honors the SAME two env vars, so a manual walkthrough against a
non-default `CTREE_PORT` can point both the hook-triggered writes and the
server's reads at one shared sandbox directory without ever touching the
live production cockpit's `~/.claude/state`.

## Event schema (finalized — Task 2)

Machine-checked shape contract:
`adapters/claude-code/schemas/progress-log-event.schema.json` (JSON Schema
draft 2020-12, `additionalProperties:false` — an ALLOWLIST, same ethos as
the landing-payload schema Task 11 builds). Every event line has this EXACT
field set; optional fields not supplied by a given type are still present
as empty strings, never omitted:

```
{v, event_id, ts, ask_id, type, plan_slug, task_id, sha, needs_you_id,
 session_id, summary, evidence_link, emitter, provenance, user, machine, repo}
```

### Per-event-type natural-key dedup table (binding; plan Task 2)

| type | natural key (dedup) | legitimate recurrence preserved |
|---|---|---|
| `task_done` | plan_slug+task_id+sha | re-verify after revert = new sha |
| `task_started` | plan_slug+task_id+session_id+**per-dispatch replay token** (`--dedup-extra`) | re-dispatch of a failed task = new dispatch (see note) |
| `waiting_on_operator` | needs_you_id | each parked decision has its own id |
| `merged` | repo+sha | every merge is its own sha |
| `plan_amended` | plan_slug+content-hash of the **pre→post delta + a replay token** (`--dedup-extra`) | second amendment = new hash, *even if it repeats a prior scope state* |
| `plan_completed` | plan_slug+content-hash of the Status-line ts (`--dedup-extra`) | re-close after reopen = new Status-line ts → new hash |
| `ask_registered` / `session_attached` | ask_id(+session_id) | attach per (ask, session) pair |
| (any other/future type) | a superset hash of every field supplied | never silently un-deduped, never wrongly collapses a real recurrence |

Superset rule (round-2 review, binding): every row's dedup-key column must
be a superset of the discriminators its recurrence column names — audited
across all rows; `plan_completed` is the one row this caught (a bare
`plan_slug` key would have suppressed a legitimate re-close after reopen).

**Superset-rule re-audit (2026-07-14 ask-splice review panel) — two rows
were violating it in the REAL caller, and both are fixed:**

- **`task_started` (was Major).** The key named `session_id` and the
  recurrence column named "new child session" — but the real emitter,
  `hooks/workstreams-emit.sh`'s `_emit_dispatch_provenance`, passes the
  **dispatching orchestrator's** `CLAUDE_SESSION_ID`, which is *invariant
  across every dispatch it makes*. So a within-session **re-dispatch of a
  failed task produced an identical key and was silently DROPPED** — the
  key was not a superset of its own recurrence discriminator. (`child_id`
  is no help: it is a pure function of that same sid.) The emitter now also
  passes a **per-dispatch replay token** as `--dedup-extra`
  (`_dispatch_replay_token`), and `_pl_natural_key` includes it. That token
  is a DEBOUNCE anchored at the FIRST fire of a given (session, plan, task):
  a re-fire within `DISPATCH_REPLAY_DEBOUNCE_SECONDS` (default **30**) reuses
  the same token (hook double-fire → still deduped), while a dispatch after
  that window mints a new one (genuine re-dispatch → a new event). Two
  sizing notes learned the hard way, both caught by the regression tests:
  (a) a naive `floor(now/N)` wall-clock bucket is NOT safe — two fires
  milliseconds apart can straddle a bucket boundary and DUPLICATE the event;
  a first-fire debounce has no boundary to straddle. (b) The window's lower
  bound is NOT sub-second: each fire forks a whole hook process (bash + git +
  sha1sum), which costs SECONDS on the Windows/Git-Bash target — a 5s window
  was measurably too tight. 30s clears a double-fire with margin and stays far
  below any real re-dispatch cycle (dispatch → build → verify = minutes).
- **`plan_amended` (was Minor).** The key hashed the **full resulting
  scope**, not the delta, so returning the scope to a previously-seen exact
  state (`A → A,B` / `A,B → A` / `A → A,B`) made the 3rd amendment collide
  with the 1st. `hooks/plan-lifecycle.sh`'s
  `emit_plan_amended_progress_log_events` now hashes the **pre→post delta
  plus a replay token** (`_amendment_replay_token` — the same first-fire
  debounce, `AMENDMENT_REPLAY_DEBOUNCE_SECONDS`) — a repeat of a prior scope
  state is a genuinely distinct amendment, while a hook re-fire of ONE edit
  still dedups. (Hashing the delta alone is NOT sufficient: in the
  `A → A,B` / `A,B → A` / `A → A,B` sequence the 1st and 3rd transitions are
  textually identical in BOTH pre and post.)

Lesson for future rows: the superset audit must be done against **what the
real caller actually passes**, not against the field's name. A self-test
that hand-feeds two different `session_id`s "proves" a recurrence the
production call site can never produce — that false assurance is exactly
what hid the `task_started` defect. The regression tests now drive the real
caller (`workstreams-emit.sh --on-builder-dispatch`, twice, with the SAME
session id).

Implemented in `hooks/lib/progress-log-lib.sh`'s `_pl_natural_key`; the
`emit` CLI's invocation shape (verbs/flags) is UNCHANGED from Task 1 — the
table above was already implemented in full by Task 1's walking skeleton,
Task 2 only hardens the writer around it (see below) and adds the machine-
checked schema file.

### Emitter allowlist + provenance (constraint 10)

`_PL_KNOWN_EMITTERS` = `plan-lifecycle`, `workstreams-emit`, `needs-you`,
`post-commit`, `close-plan`, `ask-registry`, `auditor`. An `--emitter`
outside this list is still recorded verbatim (never dropped) but stamped
`"provenance":"unknown"` — Task 12's auditor badges these and the UI
de-emphasizes them; never rendered as mechanism truth. The open CLI cannot
impersonate a mechanism by lying about its emitter name.

### ask-id path-traversal sanitizer (Task 2, security boundary)

`pl_path_for` composes `<state-dir>/<ask_id>.jsonl`, so an `ask_id`
containing `/`, `\`, or `..` would be a path-traversal write primitive. The
shared lib closes this at the boundary that protects EVERY emitter at once:
`_pl_sanitize_ask_id` allowlist-normalizes the id (every char outside
`[A-Za-z0-9._-]` — crucially the path separators — becomes `_`, then any
residual `..` run is collapsed), so the composed path is ALWAYS a single
component directly under the state dir and can never escape. A legitimate
registry ask-id (e.g. `ask-20260710-workstreams-rebuild`) is entirely
in-allowlist and passes through unchanged; a degenerate result (`.`, `_`,
empty) falls back to a deterministic `sanitized-<hash>` token so two
distinct bad ids never silently merge. Because this lives in the lib, no
individual caller (plan-lifecycle, ask-registry, needs-you, …) can forget
it. Self-test scenarios 1c/1d prove `../../evil`, `a/b/c`, `/etc/passwd`,
and the backslash variant all stay under `pl_state_dir` and that a real
emit with a traversal id writes inside the state dir with no literal
`evil.jsonl` escaping.

### Writer hardening (Task 2)

`pl_emit`'s dedup-check + append is wrapped in a `mkdir`-based inter-process
mutex (`_pl_acquire_lock`/`_pl_release_lock`) so a live splice racing the
Task 12 auditor's backfill of the identical natural key — or two hook
replays — cannot both slip past the check and double-append (a gap the
Behavioral Contracts section explicitly calls out). `mkdir` is atomic even
on Windows/NTFS via Git Bash, so no `flock`/`lockfile` binary is required.
The lock spins for a bounded ~150ms budget and then proceeds UNLOCKED
rather than hang the caller (writer semantics, constraint 5 — never
blocks); a crashed lock-holder just leaves a stale lock directory the next
caller's bounded spin times out past, no manual cleanup needed.

Self-test coverage (`progress-log-lib.sh --self-test` and
`progress-log.sh --self-test`) now includes, beyond Task 1's replay-dedup/
legitimate-recurrence/unknown-emitter/sandbox-only scenarios: concurrent-
append of distinct natural keys from parallel processes (no interleaving/
corruption), concurrent-append RACE on the identical natural key across
both same-process and real cross-OS-process invocations (dedups to exactly
one line — proves the lock), CRLF-safety (embedded CR/LF/tab in field
values never leak raw control bytes; the log file's own line terminator
stays bare LF — checked via `od -tx1` hex bytes, since MSYS text tools can
mask CRLF), and schema-field-parity (an emitted event's field set matches
`progress-log-event.schema.json`'s allowlist exactly, so an undocumented
field addition is self-test-visible, not silent drift).

## Background auditor + drift badges (Task 12)

`neural-lace/workstreams-ui/server/auditor.js` — a background reconciler
that compares the progress log against several independent ground-truth
sources and either HEALS a gap (backfills a missing event, silently) or
BADGES it (when the log claims something ground truth does not support).
It reuses `derive-cache.js`'s `bashBin()`/`spawnEnv()` spawn plumbing and
shells to the SAME mechanism CLIs every splice already uses — it never
re-implements their logic:

- `scripts/progress-log.sh emit` — backfills a missing `task_done` event.
- `scripts/ask-registry.sh set-status` — the mechanical ask-done exit
  (`--emitter auditor`).
- `hooks/lib/merge-scan-lib.sh scan-repo` — the GUARANTEED `merged`-backfill
  lane (Task 5b); this is the module Task 5b's header names as its caller.

**Cadence:** default 120000ms (2 minutes), env-tunable via
`AUDITOR_CADENCE_MS`. Deliberately relaxed relative to `derive-cache.js`'s
30s pane refresh — nothing on the `GET /api/asks` read path depends on the
auditor's freshness (the log is primary; Behavioral Contracts: "auditor
down -> landing still serves"). Single-flight guarded (a slow cycle SKIPS
the next tick rather than stacking, mirroring `DeriveCache`'s own
`_cycleInFlight`). `AUDITOR_REPO_ROOTS` (a `path.delimiter`-separated list)
overrides the repo-scan set for a sandboxed run; production resolves every
distinct root from `config/projects.js`'s `loadProjects()` map.
`AUDITOR_DISABLED=1` gates the autostart timer/immediate-fire only — a
direct `runCycle()` call is always honored (used by self-tests that need
sandboxing in place first).

### Drift taxonomy (the divergence-class table)

| Divergence | Authoritative side | Auditor action |
|---|---|---|
| checkbox `[x]`, no `task_done` event (truth ahead) | plan file | BACKFILL `task_done`, `emitter=auditor` — HEALS, no permanent badge |
| master SHA, no `merged` event (truth ahead) | git | BACKFILL `merged` via merge-scan-lib.sh's GUARANTEED lane |
| NEEDS-YOU item resolved, pointer unchecked (truth ahead) | ledger (NEEDS-YOU.md's rendered "Awaiting your decision" section) | derive resolution -> auto-check the `docs/operator-todo.md` AUTO pointer bullet |
| all linked plans terminal (`Status: COMPLETED`), ask still `active` (truth ahead) | plan Status | `ask-registry.sh set-status done`, `emitter=auditor` — the mechanical ask exit (constraint 7) |
| `task_done` event, checkbox unflipped (log ahead) | plan file | BADGE `log_ahead_task_not_flipped` — never un-emit, never flip (constraint 6) |
| `task_started` with no matching dispatch-provenance marker (log ahead) | dispatch records | BADGE `unmatched_dispatch` |
| `waiting_on_operator` with no ground truth anywhere (log ahead) | ledger | BADGE `orphaned_waiting_item` |
| event with `provenance:unknown` emitter (no oracle) | — | BADGE `unknown_provenance` + `de_emphasize:true` (constraint 10) |

"Terminal" for the plan-Status row is scoped strictly to the literal value
`COMPLETED` — deliberately not `ABANDONED`/`DEFERRED`/`SUPERSEDED` (this
estate's other terminal-ish plan statuses), since those mean "this plan
stopped", not "the ask this plan served is done."

Every drift badge carries a `detail_ref` (an opaque, stable id) and a
`message` (plain operator prose — never a raw event `type`/hook/script
name); `divergence_class` is a short, prose-safe label. Badges reach
`GET /api/asks` (ask-card level, `drift_badges[]`) and `GET /api/ask/<id>`
(ask-level `drift_badges[]` AND the matching `plan_rows[].tasks[].drift_badges[]`
row) through `payload-schema.js`'s allowlist like every other field — Task
13 (not built by this task) owns the actual click-through UI.

### §8-3 count reconciliation

Every cycle also compares the count of currently-OPEN NEEDS-YOU decisions
(parsed from NEEDS-YOU.md, the same shape `server.js`'s own reader parses)
against the count of those ids actually reflected across every ask's
`waiting_on_operator` events. A mismatch (an open decision no ask's log
references at all — it would otherwise silently vanish from the landing)
is recorded ONLY in `diagnostics.count_reconciliation`
(`GET /api/diagnostics/drift`) — deliberately NEVER a per-ask badge and
NEVER a landing-page banner (anti-noise, constraints 1/2): a systemic
mismatch may not trace to any single ask card, so the diagnostics tab
(Task 16, not built by this task) is its home.

### Diagnostics endpoint

`GET /api/diagnostics/drift` returns the auditor's FULL internal state
(healed backfills, backfill errors, the count-reconciliation detail, the
raw per-ask badge map) — deliberately NOT schema-validated (unlike
`/api/asks`/`/api/ask/<id>`), matching the existing `/api/reconciler`
precedent: the anti-noise law scopes to the LANDING payload/DOM, not this
diagnostics-only surface.

## Metrics + falsifiers (Task 17 — mirrors design sketch §8)

Each P1 success metric is PRE-REGISTERED with a mechanism that keeps it
honest and a falsifier that says what "broken" looks like — so the metric
cannot silently rot the way the old event-sourced tracker did (0 production
decision-events ever recorded, with nothing that ever went RED).

| # | Metric | Mechanism (what makes it true) | Falsifier (what "broken" looks like) |
|---|---|---|---|
| 1 | **Context-reestablishment** — operator cold-starts any active ask in <60s via the surface | Task 18 acceptance walkthrough at real registry volume, RE-FIRED every 2 weeks by a CALENDAR task (`scripts/ask-cockpit-checkin.sh` registered via `install-weekly-hygiene-task.ps1 -Checkin`) that writes the cold-start question into `~/.claude/state/external-monitor-alerts/`, surfaced at the next session by the wired `hooks/external-monitor-alert-surfacer.sh` | operator observed scroll-hunting a transcript again instead of reading the card |
| 2 | **Zero telemetry on the landing page** — landing payload/DOM carry no gate/hook identifier and no relative href | `server/payload-schema.js` `validateLanding`/`validateAskDetail` run at serve time (500-on-fail, never leak) AND in `server.selftest.js` (S27/S27a–d Task 11 + S50–S53 Task 17) AND surfaced live by the doctor: `harness-doctor.sh`'s `obs-cockpit-fresh` reads `/api/asks` and REDs on the server's own `"payload schema validation failed"` verdict | a gate/hook identifier or relative href reaches the landing builder (doctor REDs; serve-time validation 500s) |
| 3 | **Waiting-on-you completeness+dedup** — every open NEEDS-YOU item is accounted for across the landing | `server/auditor.js`'s `count_reconciliation` (ledger-parsed open ids vs ids rendered across every ask's `waiting_on_operator` events) every cadence; pinned by `server.selftest.js` S54–S56; surfaced live by the doctor: `obs-cockpit-fresh` reads `/api/diagnostics/drift` and REDs on `count_reconciliation.mismatch:true` | an open decision exists that no ask's log references — it would vanish from the landing (doctor REDs; the id is listed in `unaccounted_needs_you_ids`) |
| 3b | **Automatic-capture completeness** — every trailing-24h OPERATOR-origin session has a registered ask | `harness-doctor.sh`'s `obs-ask-capture-completeness` predicate counts ONLY operator-origin sessions — classified by the SAME `pl_classify_session` (`hooks/lib/progress-log-lib.sh`) the Task 9 capture guard uses (POPULATION PARITY: spawned/worktree sessions are excluded by construction, so orchestrated days never false-RED) — and derives each session's expected ask via the SAME `pl_ask_id_for_session` derivation the capture splice uses | a real operator session ran with no `ask_registered` record (doctor REDs, naming the session ids) — the Task 9 splice mis-fired or the registry write failed |
| 4 | **Invariant-class health** — the surface inherits the lobotomy/health/restart contract | `/api/health` grading (master `02ff2f3`); `obs-cockpit-fresh` RED on `lobotomized:true` | a lobotomized cockpit renders stale/empty panes (pre-existing doctor RED) |

Where the mechanism lives, verbatim: the doctor predicates (metrics 2, 3,
3b) are all in `adapters/claude-code/hooks/harness-doctor.sh` —
`check_obs_cockpit_fresh` was EXTENDED (not duplicated) for metrics 2 and 3;
`check_obs_ask_capture_completeness` is the new predicate for metric 3b. The
2-week check-in (metric 1) is `adapters/claude-code/scripts/ask-cockpit-checkin.sh`
+ the `-Checkin` mode of `adapters/claude-code/scripts/install-weekly-hygiene-task.ps1`.

**Population-parity law (why metric 3b cannot false-fire).** A doctor
predicate that audits a population MUST name its population filter
IDENTICALLY to the mechanism it audits. `obs-ask-capture-completeness`
sources `progress-log-lib.sh` and calls `pl_classify_session` — the exact
function Task 9's `hooks/workstreams-read.sh` capture splice calls to decide
who registers an ask — so a spawned/builder/sub-agent session (cwd under a
`.claude/worktrees/` pool, OR matched by a Task 3 dispatch-provenance
marker) is excluded from BOTH sides by construction. A re-derived or looser
filter here would RED on every orchestrated day, which is the exact drift
review round 1 (systems Minor 8) flagged; the parity is verified by the
`o6-capture-parity-spawned-excluded` doctor self-test fixture (a registered
operator session + an UNregistered spawned session → stays GREEN).

## Auditor cadence tuning

Default `120000ms` (2 min), env-tunable via `AUDITOR_CADENCE_MS`. Raise it
when the estate has many repos and the git-scan lane dominates a cycle
(check `GET /api/diagnostics/drift`'s `last_cycle_duration_ms`); lower it
only if a specific workflow needs faster drift-badge convergence and the
cycle is comfortably under the interval. The cadence is deliberately relaxed
relative to `derive-cache.js`'s 30s pane refresh — nothing on the
`GET /api/asks` read path depends on the auditor's freshness (the log is
primary), so a slow auditor degrades to STALER drift badges, never a slower
landing. Single-flight guarded: a cycle that overruns the interval SKIPS the
next tick rather than stacking.

## JSONL archival convention (done/dismissed asks)

Per-ask log files (`~/.claude/state/progress-logs/<ask-id>.jsonl`) are
append-only and bounded by being per-ask. When an ask reaches `done` or
`dismissed` AND has had no new event for a long retention window, its log
file may be moved to `~/.claude/state/progress-logs/archive/` — the readers
(`server.js`, `auditor.js`) scan only the top-level dir, so an archived log
drops out of the active surface without deletion (recoverable). P1 ships the
CONVENTION only; automated enforcement lands when volume warrants it (per
Systems Analysis §9 — volume is tens of events/day/ask today, so no sweep is
needed yet).

## "Surface looks wrong" triage order

When the landing looks wrong, trust the FILES over the UI, in this order:

1. **Doctor predicates first** — run `bash adapters/claude-code/hooks/harness-doctor.sh --quick`
   and read `obs-cockpit-fresh` (schema-leak / reconciliation-mismatch /
   lobotomy) and `obs-ask-capture-completeness` (a session with no
   registered ask). A RED here names the mechanism that broke.
2. **Diagnostics tab / endpoint** — `curl http://127.0.0.1:7733/api/diagnostics/drift`
   for the full auditor state: `count_reconciliation` (incl.
   `unaccounted_needs_you_ids`), `healed_recent`, `backfill_errors`, the raw
   per-ask badge map.
3. **The logs** — `~/.claude/logs/progress-log-emit.log` for emission
   failures; the per-ask `~/.claude/state/progress-logs/<ask-id>.jsonl` for
   the raw event stream; `~/.claude/state/ask-registry.jsonl` for the
   registry records.
4. **Never trust the UI over the files.** The UI is a view; the JSONL logs +
   registry + git history fully replay any card's state (Systems Analysis
   §6). If the UI disagrees with the files, the UI is stale or wrong — fix
   the reader, never "correct" the files to match the render.

## Symptom → diagnosis → fix (from Behavioral Contracts §"Failure modes")

| Symptom | Diagnosis | Fix |
|---|---|---|
| A card's narrative has a gap (an expected event missing) | emission splice failed at emit time (best-effort, never blocks its host) | the auditor BACKFILLS truth-ahead-of-log classes (checkbox-done, merged) within one cadence; log-ahead classes wear a drift badge — check `/api/diagnostics/drift` `healed_recent`/`backfill_errors` |
| `obs-ask-capture-completeness` RED | a real operator session ran with no `ask_registered` record | check `~/.claude/logs/progress-log-emit.log` and the session's first-prompt marker under `~/.claude/state/ask-capture/`; confirm `hooks/workstreams-read.sh`'s splice fired |
| `obs-cockpit-fresh` RED "schema validation" | a gate/hook identifier or relative href reached the landing builder | `curl /api/asks` for the `diagnostics[]` detail; fix the offending field at its SOURCE (the payload builder), never by loosening `payload-schema.js` |
| `obs-cockpit-fresh` RED "reconciliation MISMATCH" | an open NEEDS-YOU decision is referenced by no ask's log | read `count_reconciliation.unaccounted_needs_you_ids`; either the NEEDS-YOU parse broke or a decision was added without a `waiting_on_operator` event |
| registry down / capture lost | file locked or a corrupt line | readers skip bad lines and surface a diagnostics count; capture-completeness predicate goes RED; re-register happens on the next prompt-marker miss |
| landing serves but badges are stale | auditor down (log is primary; landing still serves) | the existing freshness header shows age; restart the server (auditor state rebuilds on boot — stateless) |
| server down entirely | every writer keeps writing files (nothing depends on the UI being alive — the E.6 lesson) | restart via `neural-lace/workstreams-ui/scripts/launch-gui.ps1`; no data is lost |
