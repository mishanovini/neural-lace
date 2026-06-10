---
title: Deterministic Workstreams turn-emit — stop relying on orchestrator discipline
date: 2026-06-08
type: process
status: pending
auto_applied: false
originating_context: orchestrator-prime session 2026-06-08. Misha: the Workstreams UI is not kept current because the orchestrator bypasses the fence-emit Pattern (Layer D) and the decision-context-gate didn't backstop it. Discipline-based fixes are worthless — enforce DETERMINISTICALLY.
decision_needed: Build the three pieces below.
predicted_downstream:
  - adapters/claude-code/hooks/workstreams-turn-emit.sh (NEW Stop hook)
  - adapters/claude-code/hooks/decision-context-gate.sh (hard-block tightening)
  - conversation-tree-ui state-read path config (path-mismatch fix)
---

## The failure (root cause, evidence-backed)
- The emit substrate writes spawn-branches faithfully: `neural-lace/.claude/state/conversation-tree/tree-state.json` had **1079 nodes**, written 16:40. Spawn-tracking enforcement WORKS.
- BUT the orchestrator's **decisions / questions / waiting-on-Misha items** only reach the tree via the `:::decision` fence grammar that `decision-context-gate` converts. The orchestrator (me) wrote plain-prose `PAUSING:` markers instead of fences, and the gate's Tier-1 trigger did NOT catch that prose → **zero decision cards emitted** for the real items (24-proposal review, DB password, #476/#477, m162).
- **Path mismatch (also confirmed):** the 3 items the Workstreams UI shows ("apply m162", "R23 reframe", "deploy-isolation Q1") are NOT in the 1079-node file the emit writes to. So the UI reads a DIFFERENT state file than the emit updates. Even perfect emits may not reach the UI's file.
- Misha's directive: "how do we enforce this DETERMINISTICALLY?" Discipline (me authoring fences) is proven unreliable; the fix must not depend on my behavior.

## The fix — three deterministic pieces (Misha approved 2026-06-08)

### 1. Fix the state-file path mismatch (do FIRST — nothing else matters without it)
Identify the file the Workstreams UI (127.0.0.1:7733 conversation-tree-ui) actually READS, vs where `conversation-tree-emit.sh` WRITES (`neural-lace/.claude/state/conversation-tree/tree-state.json`). Make them one and the same (point the emit at the UI's file, or the UI at the emit's file). Verify by emitting a test node and seeing it appear in the UI.

### 2. NEW Stop hook: `workstreams-turn-emit.sh` — auto-emit from the transcript EVERY turn
- Runs on the Stop event, **every turn** (Misha: "every turn", not just PAUSING/BLOCKED).
- Reads the final assistant message from `$TRANSCRIPT_PATH` (agent-uneditable — the agent cannot dodge it).
- Deterministically extracts: the DONE/PAUSING/BLOCKED marker + content; decision-soliciting items; questions; "waiting on you" lines; in-flight statements; "shipped/merged" lines.
- Emits them to the conv-tree state as cards (decision-raised / question-raised / action-added / branch in-flight / concluded) via the **sole-normative state.js facade** (ADR-032 §8 — NOT a parallel writer; reuse `appendEvent`/attestation).
- **Idempotent:** key each emit by (session_id, turn_index, content-hash) so re-runs don't duplicate. Update existing cards rather than re-create.
- Does NOT rely on the agent authoring a fence — that is the whole point.

### 3. Hard-block backstop in `decision-context-gate.sh`
Tighten so a final message that solicits a decision (PAUSING marker with options, "waiting on you", enumerated choices) and produced NO corresponding emitted card BLOCKS the turn (exit 2 + retry-guard). Closes the hole where prose-decisions slipped through.

## Acceptance
- Emit a test decision in a turn → it appears as a full-content card in the Workstreams UI "Awaiting me" pane (proves path + emit).
- The 4 current real items (24-proposal review, DB password, #476/#477, m162) appear as cards.
- A turn ending with a decision but no card is BLOCKED.
- Harness-dev work-shape: all files under `adapters/claude-code/` + the conv-tree-ui; Mode: code; acceptance-exempt; `--self-test` on the new hook is the acceptance artifact.

## Do NOT
- Do NOT "clear" the 3 existing UI stubs until each is verified (m162 is still LIVE — it's a pending decision). Concluding ≠ deleting; preserve the audit trail.
