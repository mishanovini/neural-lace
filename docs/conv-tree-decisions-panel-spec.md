# Conv Tree — Decisions panel spec (Task B handoff)

> **Audience:** the next session that owns the `conversation-tree-ui/` codebase (today: the branch `claude/vibrant-fermi-acf761` per master HEAD). This is a self-contained spec — the session implementing the panel does not need to talk to anyone to make decisions about field names, endpoint shapes, or rendering rules. Everything is locked here against [ADR-043](decisions/043-decision-queue-substrate.md) and the [schema](../adapters/claude-code/schemas/decision-queue.schema.json).

## What this panel is

A new "Decisions" panel for the Conversation Tree UI. It renders the persistent Decision Queue (`~/.claude/state/decision-queue/queue.json`) so Misha can triage asks from any agent without scraping chat.

The Decision Queue is the substrate; the panel is the surface. The substrate already exists, has a stable schema, has a `--self-test`ed storage script, and is documented in `docs/dispatch-decision-queue-tools.md`. The panel reads it; it does not own it.

## Why this is a separate session's work

The conv-tree-ui codebase lives in `conversation-tree-ui/` on the `claude/vibrant-fermi-acf761` branch family (and inside that worktree). The harness branch `feat/decision-queue` that ships the substrate does not include the conv-tree-ui directory — touching both at once would force a merge that conflicts with the in-flight Conv Tree UX redesign session (referred to by Misha as `local_bcd900b8`).

The clean split: harness ships substrate + spec; the Conv Tree session implements the panel against that spec.

## Where it goes in the layout

In the in-flight v2 layout, the right column is a vertical stack of panels. Add **"Decisions"** as a new panel in that stack. Default position: between the existing "Open branches" / "Active threads" panel and the "Backlog" panel (if backlog has its own panel) — or top of the right stack if the layout doesn't have an obvious midpoint. The exact position is the UX session's call; nothing in the substrate constrains it.

## Server-side: three new endpoints

Add to `conversation-tree-ui/server/server.js`. The handlers shell out to `~/.claude/scripts/decision-queue.sh` rather than re-implementing the storage layer — this keeps the script + schema as single source of truth.

### `GET /api/decisions`

Returns the live queue, filtered + sorted. Query params:

- `?project=<string>` — filter by project (exact match).
- `?mode=QUICK|PICK|DEEP` — filter by mode.
- `?state=open|answered|superseded|moot|all` — defaults to `open`.
- `?highlighted=true|false|all` — defaults to `all`.

Response (200): the JSON array printed by `decision-queue.sh list --format json` (already sorted by `priority_score` descending).

Suggested implementation:

```js
function handleListDecisions(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const args = ['list', '--format', 'json'];
  for (const [k, v] of url.searchParams.entries()) {
    if (['project','mode','state','highlighted'].includes(k)) args.push('--' + k, v);
  }
  const proc = spawn(DECISION_QUEUE_SH, args);
  let out = '', err = '';
  proc.stdout.on('data', d => out += d);
  proc.stderr.on('data', d => err += d);
  proc.on('close', code => {
    if (code !== 0) { res.writeHead(500); res.end(JSON.stringify({error: err.trim()})); return; }
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(out);
  });
}
```

(Resolve `DECISION_QUEUE_SH` once at startup: `path.join(process.env.HOME, '.claude/scripts/decision-queue.sh')` — assumes the harness install symlinks scripts there. Falls back to repo-relative path if not installed.)

### `POST /api/decisions/:id/close`

Body: `{"answer": "...", "by": "user"}`

Shells out to `decision-queue.sh close <id> --answer ... --by user`. Returns 200 on success, 404 if not found, 400 if body malformed.

### `POST /api/decisions/:id/highlight` and `POST /api/decisions/:id/unhighlight`

Highlight body: `{"reason": "...", "level": "subtle|strong|urgent"}`

Unhighlight body: `{"reason": "..."}` (optional)

Both shell out to the corresponding subcommands. The actor (`by` field in `highlight_history`) defaults to `gui` when invoked through the server (set `DQ_ACTOR=gui` in the spawn env).

### SSE: extend `GET /api/events` OR add `GET /api/decisions/events`

Pick one of:

- **Reuse existing event stream.** Extend `broadcastState` to also fire when `~/.claude/state/decision-queue/queue.json` mtime changes. Add a new SSE event type `decisions-state` carrying the current queue snapshot.
- **Separate stream.** Add `GET /api/decisions/events` as its own SSE endpoint with `fs.watch` on the queue file's parent dir. Cleaner separation but adds a second connection per browser tab.

Either is fine. The existing single-stream design (one SSE per page) is slightly cheaper; pick that unless the decisions stream is structurally noisier than tree state.

## Frontend: the panel

Add to `conversation-tree-ui/web/app.js` + `app.css` + `index.html`.

### Layout (top-to-bottom inside the panel)

```
┌─────────────────────────────────────────────┐
│ Decisions  [open: 7] [answered today: 3]    │
│            [aging: 2] [highlighted: 1 ★]    │
├─────────────────────────────────────────────┤
│ Filters: project ▾ mode ▾ ☐ highlighted only │
├─────────────────────────────────────────────┤
│ ★ DQ-bcd...8  <project-a>  PICK    [Reply ▾]    │  ← highlighted, top of list
│   "Which deploy target for the new endpoint?"│
│   ▾ expand                                   │
├─────────────────────────────────────────────┤
│   DQ-7c2...3  <project-b>  QUICK [Reply ▾]    │
│   "Default to opt-in or opt-out for digest?" │
│   ▾ expand                                   │
├─────────────────────────────────────────────┤
│   DQ-1a4...e  cross-cutting  DEEP [Open thread] │
│   "Should we rebuild the auth layer?"        │
│   ▾ expand                                   │
└─────────────────────────────────────────────┘
```

### State badges (panel header)

Four counts, each clickable to apply the corresponding filter:

- **open**: total items with `state == 'open'`.
- **answered today**: items with `closed_at` within the last 24h (computed client-side from `closed_at` timestamps).
- **aging**: open items with `updated_at` older than 14 days (drives `priority_score`'s aging tax — UI surfaces it as its own badge).
- **highlighted**: count of `highlighted == true` items, with a ★ icon.

### Filters row

Three controls:

- **Project dropdown** — populated from `[...new Set(items.map(i => i.project))]`; defaults to "all."
- **Mode dropdown** — `all | QUICK | PICK | DEEP`.
- **"Highlighted only" checkbox** — flips the URL query.

Each change re-fetches `/api/decisions?...` with the corresponding params.

### Item row (collapsed)

Single line: `[★] [DQ-id…short] [project] [mode] [Reply ▾]   "question"`

- `★` shown when `highlighted == true`, color/intensity by `highlight_level`:
  - `subtle`: small grey star, no animation
  - `strong`: yellow star + pulsing border on the row
  - `urgent`: red star + bell badge + the row sticks to top of list
- The "Reply ▾" button expands the item inline (see below).
- Clicking anywhere on the row also expands it (and counts as engagement — see "Auto-clear on engagement" below).

### Item row (expanded — inline, not modal)

Show the structured context vertically:

```
┌─────────────────────────────────────────────┐
│ ★ Highlighted: "Blocks 8 other items..."     │  ← only if highlighted
│   (subtle / strong / urgent)                 │
├─────────────────────────────────────────────┤
│ Question:                                    │
│   <question text>                            │
├─────────────────────────────────────────────┤
│ Recommendation (Dispatch):                   │
│   <recommendation prose, 1-3 paragraphs>     │
├─────────────────────────────────────────────┤
│ Counterargument:                             │
│   <counter text>                             │
├─────────────────────────────────────────────┤
│ Consequence of deferring:                    │
│   <defer-cost text>                          │
├─────────────────────────────────────────────┤
│ Downstream impact:                           │
│   • <what>  (blocks N)                       │
│   • <what>  (blocks N)                       │
├─────────────────────────────────────────────┤
│ Dependencies / dependents:                   │
│   ↑ depends on: DQ-... (chip, clickable)    │
│   ↓ blocks:     DQ-... (chip, clickable)    │
├─────────────────────────────────────────────┤
│ Source:                                      │
│   • <link 1>  (opens in new tab or modal)   │
│   • <link 2>                                 │
├─────────────────────────────────────────────┤
│ Reply UI per mode (see below)               │
├─────────────────────────────────────────────┤
│ [Highlight ▾]  [Dismiss highlight]  [Mark moot] │
└─────────────────────────────────────────────┘
```

### Reply UI per mode

**`QUICK`:** single `<textarea>` + Send button. POST to `/api/decisions/:id/close` with `{answer: textarea.value, by: 'user'}`.

**`PICK`:** radio group bound to `options[]` (with `default: true` pre-selected). Optional comment textarea below. On Send, `answer` = `<selected option's label> — <optional comment>`. POST as above.

**`DEEP`:** single button "Start deep-dive thread →". Opens a new Dispatch link (TBD — likely `mcp://ccd_session/spawn_task` or a documented URL the host can intercept). For v1, this MAY just navigate to a stub page that explains "this needs a real conversation — open Dispatch and quote DQ-... in the prompt." A future iteration deep-links into Dispatch directly.

### Highlight controls (in expanded view)

- **Highlight ▾** — opens a small inline dialog with `level` radio (subtle/strong/urgent) and `reason` textarea. On Apply, POST to `/api/decisions/:id/highlight`.
- **Dismiss highlight** — shown only when `highlighted == true`. POST to `/api/decisions/:id/unhighlight` with `reason: 'user dismissed'`.
- **Mark moot** — opens a small dialog asking for the reason; POST to `/api/decisions/:id/close` with `{answer: reason, by: 'user'}` then immediately PATCH state to `moot` via the `update` endpoint (if exposed) or via `decision-queue.sh update <id> --field state=moot` on the server side.

### Auto-clear on engagement

When the user expands an item OR replies to it, the panel automatically calls `unhighlight` (with reason `engagement`). The `highlight_history` records the engagement event (per schema). The panel re-renders with `highlighted: false`.

The user can explicitly re-highlight via the "Highlight ▾" button if they want to mark it for later.

### Live sync

When SSE pushes a state change (`decisions-state` event), the panel re-renders. Currently-expanded items stay expanded; preserve scroll position; preserve focus on textarea if user was typing (don't blow away their draft).

If the panel is open and a new item arrives, the new item appears in priority order (which may put it at top if highlighted). A brief flash animation on the new row helps the user notice.

### Source-doc links

Each entry in `source_doc_links` is a string — either a URL (starts with `http`) or a repo-relative path (starts with `docs/`, `adapters/`, etc.).

- URLs: `<a target="_blank">` to open in a new tab.
- Paths: open in a modal that renders the file's content (server endpoint `GET /api/file?path=<safe-path>` reading from the project root with a path-traversal guard). For v1, the modal MAY just be a `<pre>` of the raw markdown; a future iteration can add markdown rendering.

## Per-project queue support (v1 simplification)

For v1, there is ONE queue file per machine. All projects' decisions land in the same file. The `project` field is used for filtering, not for separating files. If usage grows past ~500 items, a future ADR may split per project.

## Coordination notes for the implementing session

1. **Branch off `master`, not off `feat/decision-queue`.** The substrate ships independently; the panel ships independently. They compose at runtime.
2. **Read `~/.claude/scripts/decision-queue.sh` for the source of truth on subcommand args.** This spec freezes the *interface*; the script is the *implementation*.
3. **Run `~/.claude/scripts/decision-queue.sh --self-test` first** to confirm the substrate is installed on your machine.
4. **Seed the queue with a few real items** before testing the UI:
   ```bash
   ~/.claude/scripts/decision-queue.sh add --question "Test item — UI smoke" --mode QUICK --project conv-tree-ui
   ~/.claude/scripts/decision-queue.sh add --question "Test PICK" --mode PICK --project conv-tree-ui --option "A:default:Pick A" --option "B:Pick B"
   ~/.claude/scripts/decision-queue.sh highlight $(~/.claude/scripts/decision-queue.sh list --format json | jq -r '.[0].id') --reason "smoke test highlight" --level subtle
   ```
5. **Coordination with the UX redesign in-flight:** if the v2 right-column layout is still being shuffled, this panel is just another vertical stack entry — no special positioning required. If layout decisions block panel work, leave the panel hidden behind a `?feature=decisions` URL flag for v1 and surface in v2 once the column is stable.
6. **Coordination with auto-emit-to-Conv-Tree:** out of scope for v1 (per ADR-043 §7). The panel reads the queue file directly; tree events don't have to know about decisions until a future iteration adds them.

## See also

- `docs/decisions/043-decision-queue-substrate.md` — substrate ADR
- `docs/dispatch-decision-queue-tools.md` — calling convention (what Dispatch writes; this panel reads the same shape)
- `adapters/claude-code/schemas/decision-queue.schema.json` — item shape (single source of truth)
- `adapters/claude-code/scripts/decision-queue.sh` — storage layer (the server shells out to this)
- `vibrant-fermi-acf761/neural-lace/conversation-tree-ui/server/server.js` — server to extend with the three new endpoints
- `vibrant-fermi-acf761/neural-lace/conversation-tree-ui/web/app.js` — frontend to extend with the panel
