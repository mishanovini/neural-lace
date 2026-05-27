# 038 — Pending-Items Marker Convention + Auto-Extraction into the Conversation Tree

- **Date:** 2026-05-25
- **Status:** Proposed (design-only; implementation gated on Misha's authorization)
- **Stakeholders:** Misha (owner/authorizer, the "for Misha" in the markers), harness maintainers, the Conversation-Tree GUI operator, every orchestrator session that surfaces pending items
- **Supersedes / amends:** does not supersede; extends ADR 031/032/034 (Conv-Tree architecture, state schema, Dispatch-only scope) and builds on the `conversation-tree-emit.sh` `--emit-item` / `--emit-branch` / `--emit-details` / `--resolve-item` modes (shipped 2026-05-21, v1.1.5).
- **Originating diagnosis:** `docs/discoveries/2026-05-25-file-lifecycle-root-cause-chain.md` (RC4); design harvested from the stranded `docs/reviews/2026-05-20-conv-tree-session-harness-gaps.md` Gap 5 (nervous-lehmann).
- **Design plan:** `docs/plans/file-lifecycle-redesign.md` (roadmap R3 + R4)
- **Companion ADR:** `docs/decisions/037-file-lifecycle-session-artifacts.md`

## Context

Orchestrator sessions routinely surface pending items to Misha in
`**Questions for Misha**` / `**Action items for Misha**` / `**Decisions for
Misha**` sections. Those items live only in chat — they reach the Conversation
Tree's "Waiting on you" pane ONLY if a manual script (`add-pending-items.js`) is
run, which is why that dated throwaway script exists (ADR 037 RC3). nervous-lehmann
designed an auto-extraction hook (Gap 5, 2026-05-20) but it was never built, and
the design predates the `--emit-item` modes that now make it materially smaller.

The hook needs two things to be mechanical-not-advisory: (1) a **narrow, written
marker convention** so the parser has a reliable contract (the false-negative
surface is bounded only if the accepted shapes are enumerated); (2) a deterministic
**anchor** for the extracted items in the tree.

## Decision

### D1 — The marker convention (a written contract, roadmap R3)

A new rule `adapters/claude-code/rules/pending-items-marker-convention.md` specifies
the EXACT shape the orchestrator emits and the parser consumes. The convention is
deliberately narrow — narrowness is what makes the parser reliable:

- A **section header** is a line matching (case-insensitive), optionally with a
  trailing colon, one of:
  - `**Questions for Misha**` → item kind `question`
  - `**Action items for Misha**` → item kind `action`
  - `**Decisions for Misha**` → item kind `decision`
  Also accepted: the same three labels as a markdown heading (`## Questions for
  Misha`). The header MUST be alone on its own line (anchored), not mid-sentence.
- **Items** are the bullet/numbered list immediately following the header:
  `- `, `* `, `1. `, or `1) `. An item runs until the next list marker, the next
  section header, or a blank-line gap. Multi-line wrapped items are captured whole.
- The section ends at the next `**…**`/`##` header, a horizontal rule, or
  end-of-message.

The rule binds the orchestrator (emit markers in this shape) AND documents the
parser contract (these are the only shapes the hook recognizes). Items the
orchestrator wants extracted MUST be in this shape; prose mentions are deliberately
NOT extracted.

### D2 — The extraction hook (roadmap R4)

A new Stop hook `conversation-tree-extract-pending.sh`, wired alongside
`conversation-tree-emit.sh --on-stop`. It:

1. Reads the agent-uneditable `$TRANSCRIPT_PATH` JSONL and isolates the **final
   assistant message** of this turn (NOT the whole transcript — see D4 idempotency).
2. Parses pending-item sections per the D1 contract.
3. **Anchors** the items (D3).
4. For each item, pipes a JSON payload to `conversation-tree-emit.sh --emit-item`
   with `kind` ∈ {question, action, decision}, the anchor `node_id`, a
   deterministic `item_id = sha1(session_id | kind | normalized_text)`, and the
   item text. It does NOT reimplement `appendEvent` — it reuses the frozen-facade
   modes shipped 2026-05-21.
5. Is a **writer, not a gate**: every path exits 0; emission failures are logged,
   never block Stop (gate-respect.md writer-hook discipline, identical to
   `conversation-tree-emit.sh`).

### D3 — Anchor resolution

Items attach to the session's conversation branch:
- If the per-session ledger `~/.claude/state/conversation-tree-emit/opened-<sid>.jsonl`
  has a branch this session opened (a Dispatch spawn occurred), anchor to it.
- Else, the hook ensures a **conversation-root branch** for the session exists:
  emit `--emit-branch` with a deterministic `node_id = sess-<sid-hash>`, titled from
  the session's first task (derived from the transcript the same way
  `backfill-from-sessions.js` derives it — `queue-operation enqueue.content` or the
  first non-`<` user message), parented under the project/global root from
  `_project_root`. Then attach items under it.

This reuses `--emit-branch` (already shipped); no new emit mode is required. **Open
question for Misha (see plan):** whether the per-session conversation-root should
instead be created proactively at SessionStart for every Dispatch session — that is
a small extension of ADR-034's deliberate "Dispatch-conversations-only" scope and
is surfaced as a decision rather than assumed.

### D4 — Idempotency + scan-window

- `item_id` is deterministic, so re-firing on the same content is a per-file no-op
  (the state facade dedupes by event_id; ST25 already proves `--emit-item`
  idempotency).
- The hook scans only the **final assistant message per Stop fire**. Stop fires at
  each turn boundary, so each turn's surfacing is caught at that turn's Stop.
  Scanning the whole transcript would risk re-extracting historical items every
  turn; the per-message scan + deterministic id together make extraction
  exactly-once per item.

## Alternatives Considered

- **Reimplement `appendEvent` in the hook** (the original 2026-05-20 sketch,
  "~200-300 LOC bash + node"). Rejected: the `--emit-item` modes now exist; piping
  to them keeps all state writes behind the single frozen facade and shrinks the
  hook to a parser + a pipe.
- **Scan the whole transcript, dedupe by id.** Rejected as the scan window:
  deterministic ids would make it correct but wasteful (re-parsing all history every
  Stop). Final-message-per-Stop is cheaper and equally exactly-once.
- **Anchor items at the project/global root directly** (no per-session branch).
  Rejected: collapses every session's items onto one node, losing the
  conversation-shape the tree exists to show. The per-session conversation-root
  (D3) preserves it.
- **Extract on a PostToolUse / per-message hook instead of Stop.** Rejected: Stop is
  the turn boundary where the final surfacing is stable; per-message would fire on
  intermediate drafts.

## Consequences

**Enables:** pending items flow from normal orchestrator output into the tree
automatically — the difference between "Conv Tree needs manual injection per
session" (today) and "Conv Tree auto-populates" (Misha's stated goal). The dated
`add-pending-items.js` instance (ADR 037 RC3) is retired once this ships.

**Costs:** introduces a marker convention the orchestrator must follow for items to
be extracted (a small discipline, documented in the rule + reinforced by the
already-used habit). Items not in the contract shape are silently not extracted —
acceptable, because the convention is exactly the shape already in use.

**Blocks nothing:** writer hook, never gates; sessions with no markers are a silent
no-op.

## Refutation Criterion

The claim "the extraction hook can reuse `--emit-item` rather than reimplement
`appendEvent`" is PROVEN: `conversation-tree-emit.sh` self-test ST22–ST31
(2026-05-21) exercise `--emit-branch` / `--emit-item` / `--emit-details` /
`--resolve-item` and assert items land under branches with the correct kind. The
claim "final-message-per-Stop scan is exactly-once" is HYPOTHESIZED; REFUTED if a
session surfaces the same item across two turns with text normalized differently
enough that the `sha1(text)` differs — mitigated by normalizing whitespace/case
before hashing, locked by self-test FP3.
