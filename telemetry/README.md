# Telemetry System

## Overview

Neural Lace's telemetry system runs locally — all data stays on the developer's machine unless explicitly shared. It observes the harness's own behavior to enable self-evaluation and the learning loop.

## Event Types

| Event | Schema | Emitter |
|-------|--------|---------|
| Permission decisions | `schema/permission-decision.json` | Risk engine |
| Hook firings | `schema/hook-fired.json` | Hook scripts |
| Agent invocations | `schema/agent-invoked.json` | Agent launcher |
| Session lifecycle | `schema/session-lifecycle.json` | Session hooks |

## Storage

Events are stored as JSONL files in `~/.neural-lace/telemetry/` (or equivalent per-tool location). One file per event type per day:

```
~/.neural-lace/telemetry/
  permissions-2026-04-12.jsonl
  hooks-2026-04-12.jsonl
  agents-2026-04-12.jsonl
  sessions-2026-04-12.jsonl
```

## Privacy

- All telemetry is local-only by default
- Command arguments are hashed (SHA-256) in production mode; full text only in debug mode
- No telemetry is transmitted externally unless the user explicitly opts in
- Users can delete telemetry at any time: `rm ~/.neural-lace/telemetry/*.jsonl`

## Analysis

The `analyzers/` directory (planned) will contain scripts that extract patterns from telemetry:
- False positive detection (user overrides same block repeatedly)
- Novelty decay tracking (actions becoming familiar over time)
- Trust trajectory calculation
- Weekly review report generation
