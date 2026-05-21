# Conversation-Tree — Orchestrator-Emit Surface

**Status:** Active (shipped 2026-05-21)
**Owner:** the Dispatch orchestrator (and any code session that wants to surface a decision / question / action to Misha)
**Mechanism:** four new modes on the existing `conversation-tree-emit.sh` hook (`--emit-branch`, `--emit-item`, `--emit-details`, `--resolve-item`)
**Related:** ADR-031 r7/r8 (file-mediated state contract + Dispatch-only scope), ADR-032 §2 (event-type enum), ADR-034 (sub-agent Task/Agent out of scope), `rules/conversation-tree-state.md` (write the *semantically true* tree)

## Why this surface exists

The conversation tree is **not a build-task tracker**. It is a fixture of the conversation between Misha and the orchestrator that exists for one purpose: **act as Misha's to-do list for the things only he can act on**, because he is the orchestrator's bottleneck.

Before this surface, the emit hook only fired on Dispatch spawn tools (`mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task`), emitting `branch-opened` events. That captured the *containers* (branches) but not the *contents* (decisions Misha needs to make, questions awaiting his input, actions only he can take). The tree felt stale even during active conversations because the substantive surfacing-to-user content had no path into the state file.

This document records the surface that closes that gap. The conversation-tree-emit hook now exposes four orchestrator-callable modes that emit ADR-032 §2 events — `decision-raised`, `question-raised`, `action-added`, `item-details-set`, `answered`, `action-done`, `item-backlogged` — through the same `_emit_dual` facade that powers `--on-spawn`. No new write path; no MCP server; no message-marker parser.

## When the orchestrator emits

**Emit whenever something is genuinely waiting on Misha.** The bar: would this still need to be in the tree a day from now if Misha didn't see it? If yes, emit.

Concrete trigger patterns:

- **Misha must make a decision the orchestrator cannot decide for him** — irreversible op, ambiguous product call, "either way works" choice with interface impact (per `~/.claude/rules/planning.md` "Plan-Time Decisions With Interface Impact"). Use `--emit-item kind=decision` with `details.options` carrying the alternatives + pros/cons.
- **Misha is the only source of an answer** — a credential, a domain-specific business call, a relationship he holds (per the N-R-B invisible-knowledge prompt). Use `--emit-item kind=question`.
- **An action only Misha can take** — sign up for a third-party service, click a billing link, paste back credentials, schedule a meeting, take a real-world action. Use `--emit-item kind=action`.
- **A new conversation thread that didn't come from a Dispatch spawn** — the orchestrator wants to track a topic explicitly. Use `--emit-branch` to create the container, then `--emit-item` for the contents.

**Don't emit:**
- AI-internal mechanics (peer review, verification, sub-agent dispatch) — those are sub-agent Task/Agent calls and are deliberately out of scope per ADR-034.
- Work the orchestrator can do autonomously without Misha — that's a plan task / backlog entry, not a conversation-tree item.
- Cosmetic status updates ("I started phase 2") — the tree is for *what waits on him*, not narration.

## The four modes

Every mode reads a JSON payload from stdin and is invoked via Bash:

```bash
bash ~/.claude/hooks/conversation-tree-emit.sh --emit-item <<'JSON'
{ ...payload... }
JSON
```

### `--emit-branch` — create a conversation thread

```json
{
  "node_id": "vercel-migration",
  "parent_id": "root-sprint",
  "title": "Vercel migration / hosted-routes decision"
}
```

- `node_id`: kebab-case, ASCII, stable identifier (avoid renaming — artifact correlation depends on it).
- `parent_id`: either an existing `node_id`, `"global"` for an unparented thread, or `null` for a root. Most threads should hang off `root-sprint` or another high-level program node.
- `title`: short, descriptive — appears verbatim in the GUI tree.
- **Idempotent.** Re-firing with the same `node_id` is a no-op.

### `--emit-item` — raise an item under an existing branch

```json
{
  "kind": "decision",
  "node_id": "vercel-migration",
  "item_id": "i-vercel-approach",
  "text": "Choose between (a) bisect, (b) hosted-routes-only, (c) full Vercel migration",
  "details": {
    "description": "...full prose...",
    "options": [
      {"label": "(a) Bisect first", "pros": "cheapest", "cons": "doesn't resolve long-term"},
      {"label": "(b) Hosted-routes only", "pros": "smaller blast radius", "cons": "two-host complexity"}
    ],
    "recommendation": "Orchestrator's lean is (a); needs Misha's call.",
    "blocking_input": "Misha picks (a), (b), or (c).",
    "links": ["(see branch: Vercel migration / hosted-routes decision)", "docs/architecture/example.md"]
  }
}
```

- `kind`: one of `decision`, `question`, `action`.
- `node_id`: must reference an existing branch (the reducer rejects items on unknown nodes).
- `item_id`: kebab-case, ASCII, unique within the branch. Convention: prefix with `i-` so it's visually distinct from `node_id`s.
- `text`: short one-line header for the item — appears in the "Waiting on you" pane.
- `details` (optional): the rich-detail payload the GUI's detail pane renders. Fields:
  - `description` (string): supporting prose. Omit if `text` already says everything; the GUI suppresses redundant descriptions.
  - `instructions` (string): concrete steps Misha takes — the load-bearing field for actionability.
  - `options` (array of `{label, pros, cons}`): for decisions with explicit choices.
  - `recommendation` (string): the orchestrator's lean. Always include for decisions.
  - `blocking_input` (string): what specifically unblocks the item.
  - `context` (string): supporting info that doesn't fit anywhere else.
  - `links` (array of strings): doc paths (`docs/foo.md`) or `(see branch: TITLE)` references — both become clickable in the GUI.

  When `details` is provided, a second event (`item-details-set`) is emitted in the same batch. The GUI renders an "incomplete metadata" badge on items lacking actionable fields (`instructions`/`recommendation`/`blocking_input`/`options`); always include at least one of those.

- **Idempotent on `(kind, node_id, item_id)`.** Re-firing the same item is a no-op.

### `--emit-details` — set/replace rich details on an existing item

```json
{
  "node_id": "vercel-migration",
  "item_id": "i-vercel-approach",
  "details": { ... }
}
```

Use when the orchestrator learns more about an item AFTER raising it — for example, Misha resolves an upstream blocker and the orchestrator can now fill in `options`. Last-writer-wins: the new `details` payload replaces the previous one.

### `--resolve-item` — close an item

```json
{
  "node_id": "vercel-migration",
  "item_id": "i-vercel-approach",
  "resolution": "answered"
}
```

- `resolution`: one of:
  - `answered` — for decisions/questions Misha answered.
  - `done` — for actions Misha completed.
  - `backlogged` — moves the item out of "Waiting on you" without checking it (use when the item's relevance has lapsed but the work is still tracked elsewhere).

Per ADR-032 §2, the reducer rejects `answered` on action items and `done` on decision/question items, so pick the right resolution per item kind.

## Idempotency and write semantics

Every emit derives a deterministic `event_id` from the (event-type, `node_id`, `item_id`) tuple. The state library's `appendEvent` facade dedupes per-file on `event_id`, so re-firing the same emit is a no-op. This makes the surface safe to invoke speculatively — emitting an item the orchestrator already raised is harmless.

The hook writes to BOTH sinks (per the existing `_emit_dual` discipline):

1. **GUI sink** — the main-checkout `neural-lace/conversation-tree-ui/state/tree-state.json` (resolved via `_resolve_gui_state_path`, which is worktree-aware and follows `git rev-parse --git-common-dir`). This is the file the running GUI server watches.
2. **Gate sink** — the ADR-032 §5 path (`.claude/state/conversation-tree/tree-state.json`), only when it differs from the GUI sink. Keeps the conv-tree gates' truth in sync.

Per ADR-031 r7 (writer-satisfies-gate), the emit modes write the *semantically true* tree the gates check for — not a placeholder. The Pattern in `rules/conversation-tree-state.md` binds the orchestrator: the branch and items emitted must correspond to actual conversation content, not theatrical placeholders.

## Failure isolation

Every emit mode is a writer hook, never a gate. Per the existing `_die_safe` discipline, any unexpected error (malformed JSON, missing node, schema rejection) logs to `~/.claude/logs/conversation-tree-emit.log` and exits 0 — the orchestrator's tool call is never blocked. The reducer's rejection of a malformed event is recorded in the snapshot's `rejections[]` array (per ADR-032 §6 "nothing silently dropped"), so a human auditor can see what was attempted and why it was refused.

## Self-test coverage

`bash ~/.claude/hooks/conversation-tree-emit.sh --self-test` exercises 31 scenarios as of 2026-05-21. The 10 new scenarios for the orchestrator-emit surface:

- ST22 — `--emit-branch` creates a root node
- ST23 — `--emit-item` decision lands on branch
- ST24 — `--emit-item` with details populates `item.details`
- ST25 — `--emit-item` idempotent on `(kind, node, item)`
- ST26 — `--emit-details` applied after item raised
- ST27 — `--resolve-item answered` checks a decision
- ST28 — `--resolve-item done` checks an action
- ST29 — malformed `--emit-item` (missing required key) → no-op + exit 0
- ST30 — `--emit-item` unknown kind → no-op + exit 0
- ST31 — `--emit-branch` idempotent on `node_id`

The existing 21 scenarios (ST1-ST21) for spawn/stop/worktree/sentinel parsing remain unchanged.

## Out of scope (deliberately)

- **Sub-agent `Task` / `Agent`** — AI-internal mechanics, never tree-emitting (ADR-034).
- **Polling, watching, server-push** — the GUI already watches the state file; emit writes, the GUI reacts. No additional infrastructure.
- **MCP server / new tool** — the existing Bash invocation through the hook is sufficient. Adding an MCP server would mean a long-running process to keep alive; the hook is invoked on-demand.
- **Editing items from the GUI side** — that's the GUI's own write path (handled by `server.js` POST endpoints + `actor: "gui"`). The orchestrator's emit always uses `actor: "dispatch"`.

## Adoption convention

When the orchestrator sends a response to Misha that contains:
- a decision he must make → emit `kind=decision` before/after the response (and reference the branch+item in the response so he knows where it landed)
- a question he must answer → emit `kind=question`
- an action only he can take → emit `kind=action`
- a topic that warrants its own thread → emit `--emit-branch` first

When Misha's reply resolves an item, `--resolve-item` closes the loop.

This is the conversation-as-conversation discipline: the tree IS the persistent surface of what flows between Misha and the orchestrator, and it stays current because the orchestrator emits as the conversation happens — not in a batch at the end.
