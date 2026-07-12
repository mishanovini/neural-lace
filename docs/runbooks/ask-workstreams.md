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

## Event schema (versioned; full table in Task 2)

```
{v, event_id, ts, ask_id, type, plan_slug?, task_id?, sha?, needs_you_id?,
 session_id?, summary, evidence_link, emitter, provenance, user, machine, repo}
```

Dedup is per-event-type natural key (see `progress-log-lib.sh` header for
the full table — `task_done` = plan_slug+task_id+sha, `task_started` =
plan_slug+task_id+session_id, etc.) so a hook replay never double-logs
while a legitimate recurrence (re-dispatch, re-amendment) still logs.

## What Task 17 adds here

Drift-taxonomy table (Task 12's divergence classes), the symptom -> diagnosis
-> fix table (Behavioral Contracts §"Failure modes"), auditor cadence
tuning guidance, the JSONL archival convention for done/dismissed asks, and
the "surface looks wrong" triage order (doctor predicates -> diagnostics tab
-> logs -> never trust the UI over the files).
