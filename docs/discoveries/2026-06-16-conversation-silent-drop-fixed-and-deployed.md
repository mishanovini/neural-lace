---
title: <product> conversation silent-drop fixed + deployed; harness closure machine built
date: 2026-06-16
type: failure-mode
status: implemented
auto_applied: true
originating_context: orchestrator-prime session — <product> conversation-engine silent-drop P0
---

## What was discovered
<product>'s live v1 conversation engine silently dropped customer replies: a banned NEPQ-move guard (BANNED_MOVE_USED_BLOCK) returned escalated:true, and the Trigger.dev send-gate skips escalated returns — the reply vanished (no SMS, no team signal). Audit: <product>/docs/reviews/2026-06-15-conversation-flow-silent-drop-audit.md.

## Why it matters
Customer-down P0 (One Season). Root class = a quality guard wired to veto-to-silence instead of regenerate-and-clean.

## Decision / outcome (implemented)
Repair-before-send: guard-flagged responses are regenerated into a clean compliant reply and SENT; never ship-raw, never drop, never disable a guard. <product> #533 merged 3d6e7a0e + DEPLOYED to Trigger.dev prod v20260616.1 (48 tasks). The plan-pileup root cause (plans never auto-closed) is addressed by the harness closure machine (neural-lace PR #61, R1+R2+R4). v2 cutover queued next.

## Implementation log
- <product> #533 merged 3d6e7a0e; Trigger.dev prod v20260616.1 deployed.
- neural-lace #61 (closure machine) in flight.
- Handoff: workstreams-coordination/CONVERSATION-SILENT-DROP-HANDOFF-2026-06-15.md.
