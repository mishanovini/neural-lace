# Conversation-Tree Dispatch Reader — Closing the GUI Loop

**Status:** shipped 2026-05-18 · plan `docs/plans/conv-tree-dispatch-reader.md`
**Hook:** `adapters/claude-code/hooks/conversation-tree-read.sh` (live mirror
`~/.claude/hooks/conversation-tree-read.sh`)
**Basis:** ADR-031 r7 / ADR-032 — the file-mediated state contract.

## What this closes

The Conversation-Tree UI is a file-mediated, passive-observer system
(ADR-031 r7 Option 2). It had two of the three legs of a closed loop:

1. **Claude → file (write):** `conversation-tree-emit.sh` writes
   `branch-opened` / `concluded` lifecycle events into the state file as
   Dispatch spawns and concludes child work (shipped PR #3).
2. **Human → file (write):** the GUI's symmetric `POST /api/event` writer
   (and the v1.1 inline-response UI) writes operator-authored events into the
   same state file with `actor` forced to `"gui"`.
3. **file → Claude (read):** *missing*. Operator GUI responses sat in the
   state file forever; the orchestrator never saw them unless the operator
   manually copy-pasted them into chat.

`conversation-tree-read.sh` is leg 3. It is the mirror image of the emit
hook: where the emit hook WRITES Claude's lifecycle events into the file,
the reader READS the operator's GUI responses back out and injects them into
the orchestrator's next turn — so a response the operator typed in the GUI
reaches the orchestrator exactly as if it had been typed in chat.

## Mechanism

A **UserPromptSubmit** hook (fires before each operator chat message is
processed). Registered as the last hook in the `UserPromptSubmit` chain in
both `settings.json.template` and the live `~/.claude/settings.json`, after
`goal-extraction-on-prompt.sh`.

### Output contract

UserPromptSubmit hooks: on exit 0, stdout is injected into the turn's
context. The reader emits the explicit structured form so the injection is
unambiguous and version-stable:

```json
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<block>"}}
```

Empty stdout ⇒ no context added, the prompt proceeds normally. The hook
**always exits 0** — a reader malfunction must never block or interfere with
the operator's chat message (exit 2 would block the prompt; the reader never
does that). Failures are isolated and logged to
`~/.claude/logs/conv-tree-read.log`.

### What gets surfaced

For an event to be surfaced it must be **both**:

- `actor === "gui"` — the operator authored it via the GUI. The
  orchestrator's own `actor === "dispatch"` writes (including the emit
  hook's `branch-opened`/`concluded` and the orchestrator's own `answered`)
  are **never** echoed back. This is the load-bearing exclusion.
- of a **response type** (the real ADR-032 §2 enum types that represent the
  operator communicating to the orchestrator):
  `answered`, `action-done`, `annotated`, `contested`, `contest-resolved`,
  `deferred`, `defer-cleared`, `backlog-added` — plus forward-compat names
  (`action-responded`, `action-noted-via-gui`, `question-answered`,
  `decision-made`) that are harmless if never emitted and auto-caught if the
  v1.1 UI extends the enum with them.

GUI housekeeping events (`reordered`, `draft-saved`, `re-parented`,
`draft-cleared`, …) are deliberately **not** surfaced — they are not the
operator communicating, just UI bookkeeping.

The response text is resolved from a candidate-field list (additive fields
pass the frozen `validateEvent` since it only checks required fields):
`annotated` → `.text`; `contested` → `.note`; otherwise the first non-empty
of `.response/.text/.note/.answer/.comment/.body/.message`. When no free
text is attached, a faithful description is synthesized from the event type
(e.g. `action-done` → "(marked the action complete)").

Node and item titles are resolved from the snapshot so the orchestrator
sees the branch title and the item text, not just opaque ids.

### Per-session cursor

`~/.claude/state/conv-tree-read/<session-id>.json` stores
`{last_event_id, updated_at}`. The reader walks `events[]` in **append-log
order** (the only reliable ordering — dispatch event_ids are content
hashes, not time-sortable; only GUI ULIDs sort) and surfaces everything
after the stored `last_event_id`. The cursor is advanced to the **last**
event in the log every run (even past non-response and dispatch events) so
the scan stays O(new) and nothing re-surfaces.

- **First run / no cursor / cursor compacted away** → cold start: the
  backlog is **time-bounded** (default 120 min, `CONV_TREE_READ_COLD_WINDOW_MIN`)
  so turn 1 is not flooded with a month of history. Older responses are
  intentionally not surfaced; the operator can open the GUI to review them.
- **Large backlog** → capped at `CONV_TREE_READ_MAX` (default 12), most
  recent kept, with a "(… plus N older … not shown)" notice; the cursor
  still advances so nothing re-surfaces.

### Read path

Reads **only** through the frozen A2 `state.js` `readState` facade — never
raw JSON. The facade owns parse, torn-recovery, and schema-too-new
handling; a torn / unreadable / schema-too-new file ⇒ the reader surfaces
nothing and exits 0 (logged), never crashing.

State-file resolution is byte-identical to the emit hook's GUI sink: the
**main-checkout** module `tree-state.json` the operator's single GUI server
watches (resolved via `git rev-parse --git-common-dir` so a worktree
session reads the watched file). `CONV_TREE_STATE_PATH` overrides (used by
`--self-test`).

### mtime fast-path

The GUI mutates the state file (atomic rename) only when the operator acts;
the reader advances the cursor (writing the cursor file) after reading. So
if the cursor file is **strictly newer** than the state file, nothing has
changed since the last advance — the reader no-ops **without spinning
node**. Conservative: only the strict-newer case skips; equal-mtime or
state-newer falls through to node, so a same-second write is never missed.
First run (no cursor) always falls through (cold-start must run).

## Performance (measured, honest)

On Windows git-bash the per-prompt cost is dominated by bash process
startup + subprocess overhead, not by this hook's logic:

- **Steady-state no-op turn** (operator did not touch the GUI since the
  last turn): ~300–390 ms — bash startup + a few subprocess forks; the
  mtime fast-path skips node entirely.
- **Turn where the operator responded** (node + A2 facade reduction of the
  event log): ~430–500 ms — paid only when there is something valuable to
  inject, which is exactly when the latency is justified.

The brief's `< 50 ms` target is **not achievable for any bash hook on
Windows git-bash** — bash startup alone is ~150 ms, and the sibling
per-prompt hook `goal-extraction-on-prompt.sh` (also bash + node) has the
same profile. The fast-path's real contribution is removing the *extra*
~140 ms of node + facade work on the common no-op turn; the absolute floor
is a platform property, not a defect in this hook. (Surfaced as a
friction-reflexion note — the `< 50 ms` expectation was unrealistic for
this platform/idiom.)

## Verification

`bash conversation-tree-read.sh --self-test` — **37 scenarios**, all green:
fresh/mid-stream cursor, cursor-file creation, idempotent re-fire,
dispatch-actor exclusion, housekeeping-type exclusion, `annotated`/
`contested`/`answered+response` text extraction, missing/malformed state
file, cold-start window bounding, large-backlog truncation, cursor advances
past non-response events, snapshot title/item resolution, failure isolation
(broken state-lib path), the mtime fast-path (cursor-mtime-unchanged proves
node was skipped; new event correctly forces node), and an **end-to-end
walking-skeleton slice**: facade `appendEvent({type:"answered",actor:"gui",
…response})` → fire the hook with synthetic UserPromptSubmit stdin → assert
the stdout is valid JSON with `hookEventName === "UserPromptSubmit"` and
`additionalContext` containing the operator's response text.

Regression (unchanged by this work): emit hook 17/17,
`conversation-tree-state-gate.sh` 18/18, `conversation-tree-stop-gate.sh`
8/8.

## Out of scope

The GUI (server.js / web — the v1.1 session owns the inline-response UI),
the frozen A2 state library (called, never modified), the emit hook, the
conv-tree gates, and the ADR-032 §2 enum (the reader keys off the existing
enum + forward-compat names; it never extends `schema.js`).

## Cross-references

- Plan: `docs/plans/conv-tree-dispatch-reader.md`
- Sibling writer: `adapters/claude-code/hooks/conversation-tree-emit.sh`
- Rule basis: `~/.claude/rules/conversation-tree-state.md` (ADR-031 r7
  Mechanism+Pattern split)
- ADR-031 r7 (`docs/decisions/031-conversation-tree-ui-architecture.md`),
  ADR-032 (`docs/decisions/032-conversation-tree-state-schema.md`)
- Architecture inventory row: `docs/harness-architecture.md`
  ("Claude-side reader")
