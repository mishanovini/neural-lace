# Learning Loop

## Overview

The learning loop is how Neural Lace improves itself over time. It observes behavior through telemetry, identifies patterns, generates improvement proposals, and applies approved changes.

## How It Works

```
Telemetry → Pattern Detection → Proposal → Human Review → Applied Change
```

1. **Telemetry accumulates** from every session (permission decisions, hook firings, agent invocations)
2. **Pattern detection** runs during weekly strategic reviews (and eventually continuously):
   - Hooks that never fire → candidate for removal or retargeting
   - Hooks that always pass → may be unnecessary overhead
   - Agents that produce the same finding repeatedly → candidate for a rule
   - Blocked actions the user always overrides → false positive, needs calibration
3. **Proposals** are generated and stored in `proposals/`
4. **Human reviews** proposals (via UI or CLI) and approves/rejects
5. **Approved changes** are applied and recorded in `accepted/`
6. **Rejected proposals** are stored in `rejected/` — the system learns not to re-propose

## Proposal Format

```json
{
  "id": "proposal-2026-04-12-001",
  "created": "2026-04-12T15:00:00Z",
  "type": "risk-profile-adjustment",
  "source": "telemetry-pattern",
  "description": "npm install has been confirmed 12 times with 0 rejections. Recommend lowering from T2 to T1.",
  "evidence": {
    "observations": 12,
    "overrides": 0,
    "time_span_days": 14
  },
  "proposed_change": {
    "file": "patterns/risk-profiles/actions.jsonl",
    "profile_id": "npm-install",
    "field": "dimensions.B",
    "from": 2,
    "to": 1
  },
  "status": "pending"
}
```

## Directories

- `proposals/` — Pending improvement proposals awaiting review
- `accepted/` — Applied proposals (retained for audit trail)
- `rejected/` — Declined proposals (retained so the system doesn't re-propose)
