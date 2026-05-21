# Plan: Conversation-Tree Orchestrator-Emit Surface (v1.1.5)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal — the bash hook's --self-test (31 scenarios; 10 new for the orchestrator-emit modes) is the acceptance artifact. The "user" of this mechanism is the orchestrator itself; the maintainer (Misha) verifies via the live GUI (browser) after backfill emits land. No product end-user.
Backlog items absorbed: none

## Goal

Extend `conversation-tree-emit.sh` with four new modes (`--emit-branch`, `--emit-item`, `--emit-details`, `--resolve-item`) so the Dispatch orchestrator can raise decision/question/action items directly into the conversation-tree state file. Before this work the emit hook only handled `branch-opened` on Dispatch spawn surfaces — substantive items (the actual to-do list of things waiting on Misha) had no path into the tree during the conversation that surfaced them. This plan closes that gap reusing the existing `_emit_dual` facade (no new write path, no MCP server, no message-marker parser).

## Scope

- IN:
  - `adapters/claude-code/hooks/conversation-tree-emit.sh` — four new orchestrator-emit modes + 10 new self-test scenarios (ST22-ST31).
  - `~/.claude/hooks/conversation-tree-emit.sh` — synced live mirror (byte-identical).
  - `docs/architecture/conv-tree-orchestrator-emit.md` — new mechanism documentation.
  - Backfill of 5 currently-open items into the live tree-state.json via the new emit modes (2 new branches: `observability-signup`, `vercel-migration`).
- OUT:
  - Schema changes (the existing ADR-032 §2 enum already covers decision-raised/question-raised/action-added/item-details-set/answered/action-done/item-backlogged — additive use only).
  - Sub-agent `Task`/`Agent` emission (deliberately out of scope per ADR-034).
  - New MCP server (rejected during design — Bash invocation through the existing hook is sufficient).
  - GUI-side editing surface (already exists separately as the `actor: "gui"` write path in `server.js`).

## Tasks

- [x] 1. Add `--emit-branch` / `--emit-item` / `--emit-details` / `--resolve-item` modes to `conversation-tree-emit.sh` reusing `_emit_dual`; validate required JSON keys; derive deterministic event_ids for idempotency — Verification: mechanical
- [x] 2. Add 10 self-test scenarios (ST22-ST31) covering: branch creation, item raising with/without details, idempotency, details replacement, item resolution (answered/done), malformed payload, unknown kind, branch idempotency — Verification: mechanical
- [x] 3. Sync extended hook to live `~/.claude/hooks/` mirror byte-identically; run live self-test — Verification: mechanical
- [x] 4. Backfill 5 currently-open items (Sentry signup, Axiom signup, Vercel-approach decision, Vercel-scope-doc question, vercel-status subscription) under 2 new branches (`observability-signup`, `vercel-migration`) using the new emit modes against the live state file — Verification: mechanical
- [x] 5. Author `docs/architecture/conv-tree-orchestrator-emit.md` documenting when/why/how to emit, the four modes' payload shapes, idempotency semantics, dual-sink writes, and the deliberately-out-of-scope items — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/conversation-tree-emit.sh` — extend with four new modes + 10 self-test scenarios.
- `docs/architecture/conv-tree-orchestrator-emit.md` — new documentation file.
- `~/.claude/hooks/conversation-tree-emit.sh` — synced live mirror (not in git; mirrored from canonical).
- Live state file: `~/claude-projects/neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json` (backfill emits — not committed to git, the live runtime artifact).

## In-flight scope updates
- 2026-05-21: original scope held — no surprises during build.

## Assumptions

- The existing `_emit_dual` facade is correct and stable; reusing it eliminates the need to design a new write path. (Verified by inspection — Phase A2 frozen surface per ADR-032 §1.)
- The reducer's existing event-type handlers (decision-raised / question-raised / action-added / item-details-set / answered / action-done / item-backlogged) cover all needed item lifecycle states without requiring schema changes. (Verified against `state/schema.js` + `state/reducer.js`.)
- Idempotency via deterministic event_id derived from (event-type, node_id, item_id) is sufficient — re-firing the same emit is a per-file no-op. (Verified by ST25 + ST31 self-test scenarios.)
- Bash invocation by the orchestrator is acceptable; no MCP-server infrastructure needed. (Confirmed by mechanism-choice analysis in the design phase — alternative (b) MCP server adds operational complexity for no gain.)

## Edge Cases

- **Malformed JSON payload** — handled: `_validate_keys` returns non-zero, hook logs + exits 0 (writer-not-gate discipline). Tested by ST29.
- **Unknown `kind` value** — handled: case statement falls through to log + exit 0. Tested by ST30.
- **Node_id doesn't exist when emitting an item** — handled by the reducer: the event is recorded in `rejections[]` per ADR-032 §6 ("nothing silently dropped"). The orchestrator can detect by reading state after emit.
- **Re-emit of same (kind, node_id, item_id)** — handled: deterministic event_id makes appendEvent dedupe. Tested by ST25.
- **`--emit-details` on non-existent item** — handled by the reducer's rejection path; no crash.
- **`--resolve-item` with wrong resolution for item kind** (e.g. `done` on a decision) — the reducer rejects per its existing invariants (ADR-032 §6); recorded in `rejections[]`.

## Testing Strategy

- `--self-test` exercise: 31 scenarios total (21 pre-existing ST1-21 + 10 new ST22-31). PASS gate: all 31 PASS.
- Sync verification: `diff -q canonical live` — must report byte-identical.
- Live state verification: jq-query the production state file post-backfill to confirm the 2 new branches + 5 items appear with correct kind/text/details.
- Idempotency live-test: re-emit one backfilled item and confirm event count for that item is still exactly 1.

## Walking Skeleton

A vertical slice through the new surface:
1. Orchestrator invokes `bash conversation-tree-emit.sh --emit-branch` with a JSON payload via stdin.
2. The hook parses the payload, validates required keys, derives a deterministic event_id, constructs a `branch-opened` event, writes through `_emit_dual` to the GUI sink (main-checkout module file).
3. The running GUI server's file watcher picks up the change and re-renders the tree.
4. Misha sees the new branch in his browser.
5. Same vertical slice for `--emit-item` (creates a decision/question/action under the branch) and `--emit-details` (populates rich detail fields the GUI renders in the detail pane).

This vertical slice was exercised end-to-end during the backfill: 2 branches + 5 items emitted; the live state file inspection (jq) confirmed all 7 events landed with correct fields and `actor: "dispatch"`.

## Decisions Log

### Decision: Mechanism choice — extend emit hook (a) vs MCP server (b) vs message-marker parser (c)
- **Tier:** 1
- **Status:** Implemented
- **Chosen:** (a) Extend the existing emit hook with new modes.
- **Alternatives:**
  - (b) New MCP server exposing `emit_item` as a tool. Pro: explicit semantics, typed args. Con: adds a long-running process, new infrastructure to keep alive, separate from the existing emit substrate.
  - (c) Message-marker pattern (`<conv-tree-emit kind="...">...</conv-tree-emit>` in orchestrator responses). Pro: zero invocation friction. Con: parser brittleness, ambiguous boundaries, mixes content with control plane.
- **Reasoning:** (a) reuses the proven `_emit_dual` facade — same idempotency, same dual-sink writes, same failure isolation — and stays symmetric with the existing `--on-spawn` path. ADR-031 r7's design instruction was that the writer writes the true tree the gate checks for; adding modes to the existing writer is the cleanest expression of that intent. No new processes, no new parsing surface.
- **Checkpoint:** N/A (no rollback needed — additive change to an existing hook).
- **To reverse:** Revert the commit; remove the four new case arms; remove ST22-ST31.

## Definition of Done

- [x] All five tasks checked off.
- [x] Self-test passes 31/31 in both canonical and live mirror.
- [x] Backfill verified via jq inspection — 2 branches + 5 items present in live state file.
- [x] Documentation file present at `docs/architecture/conv-tree-orchestrator-emit.md`.
- [x] SCRATCHPAD update reflects new mechanism (deferred to merge-commit step).
- [x] Completion report appended below.

## Completion Report

### 1. Implementation Summary
- Extended `conversation-tree-emit.sh` with four new modes (`--emit-branch`, `--emit-item`, `--emit-details`, `--resolve-item`) — 318 net new lines, all reusing the existing `_emit_dual` facade.
- Added 10 self-test scenarios (ST22-ST31) exercising branch creation, item raising (with/without details), idempotency, detail replacement, item resolution (answered/done), malformed-payload handling, unknown-kind handling, branch idempotency.
- Synced extended hook to live mirror byte-identically (`diff -q` confirmed).
- Backfilled 5 currently-open items via the new modes: Sentry signup + Axiom signup (under new `observability-signup` branch) and Vercel-approach decision + scope-doc question + status-page subscription (under new `vercel-migration` branch).
- Created `docs/architecture/conv-tree-orchestrator-emit.md` documenting when/why/how to emit, the four modes' payload shapes, dual-sink writes, idempotency semantics, and out-of-scope items.

### 2. Design Decisions & Plan Deviations
- One Decisions Log entry recorded (mechanism choice: extend hook vs MCP vs marker pattern). No deviations from the original task list.
- Path A residual decision and the existing pricing-structure item were deliberately skipped during backfill — Path A was too vague to ground responsibly; pricing-structure already had an item in the live state from prior work.

### 3. Known Issues & Gotchas
- The orchestrator should prefer creating new `node_id`s for new threads rather than reusing existing ones (the reducer treats duplicate `branch-opened` as a `rejections[]` entry, which is the correct conservative behavior but means a duplicate emit is silently no-op'd).
- `item-details-set` is last-writer-wins — sequential `--emit-details` calls overwrite each other. To merge details, the orchestrator must read the existing details, merge in code, then re-emit.

### 4. Manual Steps Required
- None. The mechanism is fully self-contained.

### 5. Testing Performed & Recommended
- 31/31 self-test PASS in canonical and live mirror.
- Live state file inspection (jq) confirmed all 7 backfill events (2 branches + 5 items) landed with correct fields.
- Re-emit idempotency confirmed in production state (event count stayed at 1).
- Recommended manual check: hard-refresh the GUI (Ctrl-Shift-R) and confirm the 2 new branches + 5 items appear with their detail content in the "Waiting on you" pane.

### 6. Cost Estimates
- Recurring cost: $0. The new modes use the same Bash + node invocation path as the existing emit; no new dependencies, no new infrastructure.
