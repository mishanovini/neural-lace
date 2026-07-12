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
| `task_started` | plan_slug+task_id+session_id | re-dispatch of a failed task = new child session |
| `waiting_on_operator` | needs_you_id | each parked decision has its own id |
| `merged` | repo+sha | every merge is its own sha |
| `plan_amended` | plan_slug+content-hash of the delta (`--dedup-extra`) | second amendment = new delta hash |
| `plan_completed` | plan_slug+content-hash of the Status-line ts (`--dedup-extra`) | re-close after reopen = new Status-line ts → new hash |
| `ask_registered` / `session_attached` | ask_id(+session_id) | attach per (ask, session) pair |
| (any other/future type) | a superset hash of every field supplied | never silently un-deduped, never wrongly collapses a real recurrence |

Superset rule (round-2 review, binding): every row's dedup-key column must
be a superset of the discriminators its recurrence column names — audited
across all rows; `plan_completed` is the one row this caught (a bare
`plan_slug` key would have suppressed a legitimate re-close after reopen).

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

## What Task 17 adds here

Drift-taxonomy table (Task 12's divergence classes), the symptom -> diagnosis
-> fix table (Behavioral Contracts §"Failure modes"), auditor cadence
tuning guidance, the JSONL archival convention for done/dismissed asks, and
the "surface looks wrong" triage order (doctor predicates -> diagnostics tab
-> logs -> never trust the UI over the files).
